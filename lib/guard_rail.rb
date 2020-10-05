require 'set'

module GuardRail
  class << self
    attr_accessor :primary_environment_name
    GuardRail.primary_environment_name = :primary

    def environment
      Thread.current[:guard_rail_environment] ||= primary_environment_name
    end

    def global_config
      @global_config ||= {}
    end

    def activated_environments
      @activated_environments ||= Set.new()
    end

    # semi-private
    def initialize!
      require 'guard_rail/connection_handler'
      require 'guard_rail/connection_specification'
      require 'guard_rail/helper_methods'

      activated_environments << GuardRail.environment

      ActiveRecord::ConnectionAdapters::ConnectionHandler.prepend(ConnectionHandler)
      ActiveRecord::ConnectionAdapters::ConnectionSpecification.prepend(ConnectionSpecification)
    end

    def global_config_sequence
      @global_config_sequence ||= 1
    end

    def bump_sequence
      @global_config_sequence ||= 1
      @global_config_sequence += 1
      ActiveRecord::Base::connection_handler.clear_all_connections!
    end

    # for altering other pieces of config (i.e. username)
    # will force a disconnect
    def apply_config!(hash)
      global_config.merge!(hash)
      bump_sequence
    end

    def remove_config!(key)
      global_config.delete(key)
      bump_sequence
    end

    def connection_handlers
      save_handler
      @connection_handlers
    end

    # switch environment for the duration of the block
    # will keep the old connections around
    def activate(environment)
      environment ||= primary_environment_name
      return yield if environment == self.environment
      begin
        old_environment = activate!(environment)
        activated_environments << environment
        yield
      ensure
        Thread.current[:guard_rail_environment] = old_environment
        ActiveRecord::Base.connection_handler = ensure_handler unless test?
      end
    end

    # for use from script/console ONLY
    def activate!(environment)
      environment ||= primary_environment_name
      save_handler
      old_environment = self.environment
      Thread.current[:guard_rail_environment] = environment
      ActiveRecord::Base.connection_handler = ensure_handler unless test?
      old_environment
    end

    private

    def test?
      Rails.env.test?
    end

    def save_handler
      @connection_handlers ||= {}
      @connection_handlers[environment] ||= ActiveRecord::Base.connection_handler
    end

    def ensure_handler
      new_handler = @connection_handlers[environment]
      if !new_handler
        new_handler = @connection_handlers[environment] = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
        pools = ActiveRecord::Base.connection_handler.send(:owner_to_pool)
        pools.each_pair do |model, pool|
          new_handler.establish_connection(pool.spec.config)
        end
      end
      new_handler
    end
  end
end

if defined?(Rails::Railtie)
  require "guard_rail/railtie"
else
  # just load everything immediately for Rails 2
  GuardRail.initialize!
end