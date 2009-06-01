require 'authenticated_system'

module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    module Owned #:nodoc:
      def self.current_user
        Thread.current[:current_user]
      end

      def self.current_user=(x)
        Thread.current[:current_user] = x
      end

      def self.default_scope_conditions(column_name = :user_id)
        {column_name => current_user ? current_user.id : nil}
      end
      
      def self.included(base)
        base.extend(ClassMethods)
      end

      # This +acts_as+ extension provides the capabilities for automatically: filtering finds with a default scope,
      # adding association a model with a user, validating the presence of the user, validating the assoociated user,
      # and ensuring that the current user is added to the model during creation.
      # The class that has this specified needs to have a +user_id+ column defined as an integer on
      # the mapped database table. The restful authenticication plugin must also be installed.
      #
      # Owned item example:
      #
      #   class OwnedItem < ActiveRecord::Base
      #     acts_as_owned
      #   end
      #
      # The above would replace (assuming that somehow you could access the current user in the model without acts_as_owned)
      #
      #   class OwnedItem < ActiveRecord::Base
      #     
      #     default_scope :conditions => {:user_id => current_user ? current_user.id : nil}
      #     
      #     belongs_to :user
      #     
      #     validates_presence_of :user
      #     
      #     validates_associated :user
      #     
      #     before_validation_on_create, Proc.new { |record| record.user = current_user }
      #     
      #   end
      #
      # If you wish some additional default scoping
      #
      #   class OwnedItem < ActiveRecord::Base
      #     acts_as_owned
      #     default_scope :conditions => { :active => true, acts_as_owned_class.default_scope_conditions }
      #   end
      #
      #      
      module ClassMethods
        # Quick access to the actual class providing acts_as_owned
        def acts_as_owned_class
          ::ActiveRecord::Acts::Owned
        end
        
        # Configuration options are:
        #
        # * +user+ - specifies the association used for the user. (default: :user)
        # The following options allow you to turn off automatic behaviors. Examples assume user option was not specified.
        # * +belongs_to+ - belongs_to :user. (default: +true+)
        # * +validates_presence_of+ - validate_presense_of :user (default: +true+)
        # * +validates_associated+ - validate_associated :user (default: +true+)
        # * +default_scope+ - default_scope :conditions => acts_as_owned_class.default_scope_conditions (default: +true+)
        # * +before_validation_on_create+ - {self.user = ActiveRecord::Acts::Owned.current_user} (default: +true+)
        def acts_as_owned(options={})

          user = options[:user] || :user         
          user = user.to_sym
          use_belongs_to = options[:belongs_to] || true         
          use_validates_presence_of = options[:validates_presence_of] || true
          use_validates_associated = options[:validates_associated] || true
          use_default_scope = options[:default_scope] || true
          use_before_validation_on_create = options[:before_validation_on_create] || true

          send(:belongs_to, user) if use_belongs_to
          send(:validates_presence_of, user) if use_validates_presence_of
          send(:validates_associated, user) if use_validates_associated
          send(:default_scope, :conditions => acts_as_owned_class.default_scope_conditions("#{user}_id".to_sym)) if use_default_scope
          send(:before_validation_on_create, Proc.new { |record| record.send("#{user}=".to_sym, acts_as_owned_class.current_user) }) if use_before_validation_on_create
        
        end
      end
    end
  end
end


module AuthenticatedSystem #:nodoc:

protected

  def current_user_with_acts_as_owned=(new_user)
    ActiveRecord::Acts::Owned.current_user = self.current_user_without_acts_as_owned=(new_user)
  end

  alias_method_chain :current_user=, :acts_as_owned

end
