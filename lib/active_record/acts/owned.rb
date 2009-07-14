require 'authenticated_system'

module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    module Owned
      def self.current_user #:nodoc:
        Thread.current[:acts_as_owned_current_user]
      end

      def self.current_user=(x) #:nodoc:
        Thread.current[:acts_as_owned_current_user] = x
      end

      def self.current_user_admin? #:nodoc:
          current_user.respond_to?(:admin?) && current_user.admin?
      end

      def self.ownership_active=(boolean) #:nodoc:
        Thread.current[:acts_as_owned_active] = boolean
      end
      
      def self.ownership_active #:nodoc:
        Thread.current[:acts_as_owned_active] = true if Thread.current[:acts_as_owned_active].nil?
        Thread.current[:acts_as_owned_active]
      end

      def self.valid_find_options #:nodoc:
        Thread.current[:acts_as_owned_active_find_options] ||= ActiveRecord::Base.class_eval { class << self; self; end }::VALID_FIND_OPTIONS
      end
      
      # Returns true if the ownership checking is currently on
      def self.ownership_active?
        ownership_active
      end
      
      # Returns true if the ownership checking is currently off
      def self.ownership_inactive?
        !ownership_active?
      end

      # Run a block with ownership checking on
      def self.with_ownership(&block)
        with_ownership_at(true, &block)
      end

      # Run a block with ownership checking off
      def self.without_ownership(&block)
        with_ownership_at(false, &block)
      end
      
      # Run a block with ownership checking on or off based on the boolean value provided
      def self.with_ownership_at(boolean, &block)
        current_value = ownership_active
        begin
          self.ownership_active = boolean
          yield
        ensure
          self.ownership_active = current_value
        end
      end
      
      # Returns the current conditions that acts_as_owned would use in the default_scope.
      def self.default_scope_conditions(column_name = :user_id)
        ownership_active? ? {column_name => current_user ? current_user.id : nil} : {}
      end
      
      def self.included(base) #:nodoc:
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
      # The above would replace (assuming that somehow you could access the current user in the model without acts_as_owned and pass blocks to default_scope)
      #
      #   class OwnedItem < ActiveRecord::Base
      #     
      #     default_scope do
      #       :conditions => {:user_id => current_user ? current_user.id : nil}
      #     end
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
      #     default_scope do
      #       conditions => { :your_value => true }
      #       conditions.merge! acts_as_owned_class.default_scope_conditions
      #       :conditions => conditions
      #     end
      #   end
      #
      #      
      module ClassMethods
        
        # Configuration options are:
        #
        # * +user+ - specifies the association used for the user. (default: :user)
        # The following options allow you to turn off automatic behaviors. Examples assume user option was not specified.
        # * +belongs_to+ - establish the association with the user. (default: +true+)
        #        belongs_to :user
        # * +validates_presence_of+ - validate the presence of the user. (default: +true+)
        #        validate_presense_of :user 
        # * +validates_associated+ - validate the associated user. (default: +true+)
        #        validate_associated :user 
        # * +default_scope+ - automatically sets up the default scope for the model. (default: +true+)
        #        default_scope do
        #          {:conditions => acts_as_owned_class.default_scope_conditions}
        #        end
        # * +auto_admin+ - if current_user responds to admin? and it returns true, then automatically pass ownership checking as if the :admin => true flag was passed for all finds done by that admin. (default: +true+)
        #        Model.find_all_by_condition(value, :admin => current_user.admin?) 
        #
        #        # can be replaced by the following to yield the same reults
        #
        #        Model.find_all_by_condition(value) 
        def acts_as_owned(options={})

          class << self
            # Quick access to the actual class providing acts_as_owned
            def acts_as_owned_class
              ::ActiveRecord::Acts::Owned
            end
          
            def validate_find_options_with_acts_as_owned(options) #:nodoc:
              options.assert_valid_keys(acts_as_owned_class.valid_find_options + [:admin])
            end

            @@auto_admin = true
            
            def auto_admin #:nodoc:
              @@auto_admin
            end
            
            def auto_admin=(value) #:nodoc:
              @@auto_admin = value
            end

            def find_every_with_acts_as_owned(options) #:nodoc:
              if options.has_key?(:admin)
                acts_as_owned_class.with_ownership_at(!options.delete(:admin)) { find_every_without_acts_as_owned(options) }
              elsif auto_admin && acts_as_owned_class.current_user_admin?
                acts_as_owned_class.with_ownership_at(false) { find_every_without_acts_as_owned(options) }
              else
                find_every_without_acts_as_owned(options)
              end
            end
            
            def find_from_ids_with_acts_as_owned(ids, options) #:nodoc:
              if options.has_key?(:admin) || (auto_admin && acts_as_owned_class.current_user.respond_to?(:admin?) && acts_as_owned_class.current_user.admin?)
                acts_as_owned_class.with_ownership_at(!options.delete(:admin)) { find_from_ids_without_acts_as_owned(ids, options) }
              elsif auto_admin && acts_as_owned_class.current_user_admin?
                acts_as_owned_class.with_ownership_at(false) { find_from_ids_without_acts_as_owned(ids, options) }
              else
                find_from_ids_without_acts_as_owned(ids, options)
              end
            end

            alias_method_chain :validate_find_options, :acts_as_owned unless method_defined?(:validate_find_options_without_acts_as_owned)
            alias_method_chain :find_every, :acts_as_owned unless method_defined?(:find_every_without_acts_as_owned)
            alias_method_chain :find_from_ids, :acts_as_owned unless method_defined?(:find_from_ids_without_acts_as_owned)

          end
          
          default_options = { :user => :user, :belongs_to => true, :validates_presence_of => true, :validates_associated => true, :default_scope => true, :before_validation_on_create => true, :auto_admin => true }
          options = default_options.merge(options)
          
          user = options[:user]
          user = user.to_sym
          use_belongs_to = options[:belongs_to]
          use_validates_presence_of = options[:validates_presence_of]
          use_validates_associated = options[:validates_associated]
          use_default_scope = options[:default_scope]
          use_before_validation_on_create = options[:before_validation_on_create]
          use_auto_admin = options[:auto_admin]

          send(:belongs_to, user) if options[:belongs_to]
          send(:validates_presence_of, user) if options[:validates_presence_of]
          send(:validates_associated, user) if options[:validates_associated]
          send(:default_scope, &Proc.new { {:conditions => acts_as_owned_class.default_scope_conditions("#{user}_id".to_sym) }}) if options[:default_scope]
          send(:before_validation_on_create, &Proc.new { |record| record.user = acts_as_owned_class.current_user; true }) if options[:before_validation_on_create]
          send(:auto_admin=, options[:auto_admin])
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
