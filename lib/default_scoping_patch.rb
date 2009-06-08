# Based on http://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets/1812-default_scope-cant-take-procs
# Adds the ability of default_scope to take procs
# Taken from http://gist.github.com/81187
ActiveRecord::Base.class_eval do #:nodoc:

  class << self
    
    private
    
      def find_last(options) #:nodoc:
        order = options[:order]

        if order
          order = reverse_sql_order(order)
        elsif !scoped?(:find, :order)
          order = "#{table_name}.#{primary_key} DESC"
        end

        if scoped?(:find, :order)
          scope = scope(:find)
          with_scope(:find => { :order => reverse_sql_order(scope[:order]) }) { find_initial(options) }
        else
          find_initial(options.merge({ :order => order }))
        end
      end
    
    protected
  
      def with_scope(method_scoping = {}, action = :merge, &block) #:nodoc:
        method_scoping = method_scoping.method_scoping if method_scoping.respond_to?(:method_scoping)

        method_scoping.assert_valid_keys([ :find, :create ])

        if f = method_scoping[:find]
          f.assert_valid_keys(VALID_FIND_OPTIONS)
          set_readonly_option! f
        end

        method_scoping = merge_scopings(method_scoping, current_scoped_methods || {}, action)
  
        self.scoped_methods << method_scoping
        begin
          yield
        ensure
          self.scoped_methods.pop
        end
      end
      
      def without_default_scope #:nodoc:
        backup_default_scoping = self.default_scoping.dup
        self.default_scoping = []
        begin
          yield
        ensure
          self.default_scoping = backup_default_scoping
        end
      end
      
      def with_exclusive_scope(method_scoping = {}, &block) #:nodoc:
        without_default_scope { with_scope(method_scoping, :overwrite, &block) }
      end
    
      def merge_scopings(new_scopings, existing_scopings, action = :merge) #:nodoc:
        # Dup first and second level of hash (method and params).
        new_scopings = new_scopings.inject({}) do |hash, (method, params)|
          hash[method] = (params == true) ? params : params.dup
          hash
        end
      
        return new_scopings unless [:merge, :reverse_merge].include?(action)
      
        existing_scopings.inject(new_scopings) do |hash, (method, params)|
          case hash[method]
            when Hash
              if method == :find
                (hash[method].keys + params.keys).uniq.each do |key|
                  merge = hash[method][key] && params[key] # merge if both scopes have the same key
                  if key == :conditions && merge
                    if params[key].is_a?(Hash) && hash[method][key].is_a?(Hash)
                      hash[method][key] = merge_conditions(hash[method][key].deep_merge(params[key]))
                    else
                      hash[method][key] = merge_conditions(params[key], hash[method][key])
                    end
                  elsif key == :include && merge
                    hash[method][key] = merge_includes(hash[method][key], params[key]).uniq
                  elsif key == :joins && merge
                    hash[method][key] = merge_joins(params[key], hash[method][key])
                  else
                    hash[method][key] = hash[method][key] || params[key]
                  end
                end
              else
                if action == :reverse_merge
                  hash[method] = hash[method].merge(params)
                else
                  hash[method] = params.merge(hash[method])
                end
              end
            else
              hash[method] = params
          end
          hash
        end
      end
    
      def eval_default_scoping #:nodoc:
        default_scoping.inject({}) do |hash, ds|
          scope_options = ds.call
        
          clean_scope_options = { :find => scope_options }
          clean_scope_options[:create] = 
            (scope_options.is_a?(Hash) && scope_options.has_key?(:conditions) && scope_options[:conditions].respond_to?(:merge)) ? 
              scope_options[:conditions] : {}
            
          merge_scopings(hash, clean_scope_options, :merge)
        end
      end
      
      def current_merged_scopings #:nodoc:
        merge_scopings(current_scoped_methods || {}, eval_default_scoping, :merge)
      end
    
      def default_scope(options = {}, &block) #:nodoc:
        raise ArgumentError.new("Cannot take options and block at the same time") if !options.empty? && block_given?
        self.default_scoping << lambda{ block ? block.call : options }
      end

      def scoped?(method, key = nil) #:nodoc:
        if scope = current_merged_scopings[method]
          !key || !scope[key].nil?
        end
      end

      def scope(method, key = nil) #:nodoc:
        if scope = current_merged_scopings[method]
          key ? scope[key] : scope
        end
      end
    
      def scoped_methods #:nodoc:
        Thread.current[:"#{self}_scoped_methods"] ||= []
      end

  end
end