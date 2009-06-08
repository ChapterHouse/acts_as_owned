$:.unshift "#{File.dirname(__FILE__)}/lib"
require 'default_scoping_patch'
require 'active_record/acts/owned'
ActiveRecord::Base.class_eval { include ActiveRecord::Acts::Owned }
