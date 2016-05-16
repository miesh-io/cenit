require 'cancan/model_adapters/mongoff_adapter'
require 'setup/storage'

class Ability
  include CanCan::Ability

  def initialize(user)
    can :access, :rails_admin
    if (@user = user)
      cannot :inspect, Account unless user.super_admin?

      can [:show, :edit], Account, id: user.account_id
      can [:show, :edit], User, id: user.id

      @@oauth_models = [Setup::BaseOauthProvider,
                        Setup::OauthProvider,
                        Setup::Oauth2Provider,
                        Setup::OauthClient,
                        Setup::Oauth2Scope]

      can [:index, :show, :edi_export, :simple_export], @@oauth_models
      if user.super_admin?
        can [:destroy, :edit, :create, :import, :cross_share], @@oauth_models
        can :manage, Setup::Application
      else
        can [:destroy, :edit], @@oauth_models, tenant_id: Account.current.id
        cannot :access, Setup::Application
      end

      if user.super_admin?
        can :manage,
            [
              Role,
              User,
              Account,
              Setup::SharedName,
              CenitToken,
              ApplicationId,
              Script,
              Setup::DelayedMessage,
              Setup::SystemNotification
            ]
        can [:import, :edit], Setup::SharedCollection
        can :destroy, [Setup::SharedCollection, Setup::DataType, Setup::Storage]
        can [:index, :show, :cancel], RabbitConsumer
      else
        cannot :access, [Setup::SharedName, Setup::DelayedMessage, Setup::SystemNotification]
        cannot :destroy, [Setup::SharedCollection, Setup::Storage]
      end

      task_destroy_conds =
        {
          'status' => { '$in' => Setup::Task::NOT_RUNNING_STATUS },
          'scheduler_id' => { '$in' => Setup::Scheduler.where(activated: false).collect(&:id) + [nil] }
        }
      can :destroy, Setup::Task, task_destroy_conds


      can RailsAdmin::Config::Actions.all(:root).collect(&:authorization_key)

      can :update, Setup::SharedCollection do |shared_collection|
        shared_collection.owners.include?(user)
      end
      can :edi_export, Setup::SharedCollection

      @@setup_map ||=
        begin
          hash = {}
          non_root = []
          RailsAdmin::Config::Actions.all.each do |action|
            unless action.root?
              if (models = action.only)
                models = [models] unless models.is_a?(Enumerable)
                hash[action.authorization_key] = Set.new(models)
              else
                non_root << action
              end
            end
          end
          Setup::Models.each_excluded_action do |model, excluded_actions|
            non_root.each do |action|
              models = (hash[key = action.authorization_key] ||= Set.new)
              models << model if relevant_rules_for_match(action.authorization_key, model).empty? && !(excluded_actions.include?(:all) || excluded_actions.include?(action.key))
            end
          end
          Setup::Models.each_included_action do |model, included_actions|
            non_root.each do |action|
              models = (hash[key = action.authorization_key] ||= Set.new)
              models << model if included_actions.include?(action.key)
            end
          end
          new_hash = {}
          hash.each do |key, models|
            a = (new_hash[models] ||= [])
            a << key
          end
          hash = {}
          new_hash.each { |models, keys| hash[keys] = models.to_a }
          hash
        end

      @@setup_map.each do |keys, models|
        cannot Cenit.excluded_actions, models unless user.super_admin?
        can keys, models
      end

      can :manage, Mongoff::Model
      can :manage, Mongoff::Record

    else
      can [:dashboard, :shared_collection_index]
      can [:index, :show, :grid, :pull, :simple_export], [Setup::SharedCollection]
      can :index, Setup::Models.all.to_a
    end
  end

  def can?(action, subject, *extra_args)
    if subject == ScriptExecution && @user && !@user.super_admin?
      false
    else
      super
    end
  end
end
