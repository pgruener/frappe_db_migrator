require 'base64'
require 'active_support/all'
require 'active_model'
require './lib/driver_base'

module Targets
  class MysqlToPostgres < DriverBase
    def initialize(config)
      super

      # init config with defaults (if necessary)
      config.config[:endpoint] ||= get_config(:endpoint, nil, 'https://frappecloud.com')
      config.config[:port] ||= get_config(:port, 'PG_PORT', '5432')
      config.config[:host] ||= get_config(:host, 'PG_HOST', 'localhost')
      config.config[:overwrite] = ActiveModel::Type::Boolean.new.cast(get_config(:overwrite, 'PG_OVERWRITE', false))

      # validate config
      if get_config(:database).blank?
        raise "Missing mysql_to_postgres *database* definition for target *#{target_ident}*"
      end

      if get_config(:username).blank?
        raise "Missing mysql_to_postgres *username* definition for target *#{target_ident}*"
      end

      if get_config(:password).blank?
        raise "Missing mysql_to_postgres *password* definition for target *#{target_ident}*"
      end
    end

    def run!
      if context[:mysql_imported_db].blank?
        raise "Missing mysql_imported_db instance in running context of target *#{target_ident}*"
      end

      pg_command = "PGPASSWORD=#{get_config(:password)} psql -h #{get_config(:host)} -U #{get_config(:username)} -d #{get_config(:database)} -p #{get_config(:port)} -t -A"
      log pg_command
      puts pg_command

      # check if postgres db exists and is empty
      case `#{pg_command} -c "\\dt" 2>&1`
      when /does not exist/
        log "Postgres DB *#{get_config(:database)}* not existing"
        return
      when /Did not find any relations/
        log "Database *#{get_config(:database)}* is empty.. loading data"
      else
        if ActiveModel::Type::Boolean.new.cast(get_config(:overwrite))
          log "Database *#{get_config(:database)}* exists and is not empty.. deleting tables (as overwrite was set to true)"

          if context[:mysql_imported_db_selected_tables]
            context[:mysql_imported_db_selected_tables].each do |table_to_drop|
              # the table names are translated to downcase (by pg migration) if no space is in the name.
              adjusted_table_name = table_to_drop.include?(" ") ? table_to_drop : table_to_drop.downcase

              log "Dropping table *public.#{adjusted_table_name}*"
              log `#{pg_command} -c 'DROP TABLE IF EXISTS public."#{adjusted_table_name}" CASCADE;' 2>&1`
            end
          else
            tables_to_drop = `#{pg_command} -c "SELECT CONCAT('DROP TABLE \\"', tablename, '\\" CASCADE;') FROM pg_tables
                                                                WHERE schemaname='public'; 2>&1`
            tables_to_drop.split("\n").each do |table_to_drop|
              log "Dropping table *#{table_to_drop}*"
              log `#{pg_command} -c '#{table_to_drop}' 2>&1`
            end
          end
        else
          log "Database *#{get_config(:database)}* exists and is not empty.. skipping (as overwrite was set to false)"
          return
        end
      end

      # import from mysql db called in context[:mysql_imported_db]
      log "Importing from mysql db *#{context[:mysql_imported_db]}* to postgres db *#{get_config(:database)}*"
      log "PGUSER=\"#{get_config(:username)}\" PGPASSWORD=\"#{get_config(:password)}\" PGHOST=\"#{get_config(:host)}\" /tmp/pgloader/build/bin/pgloader --with \"prefetch rows = 100\" mysql://root@localhost/#{context[:mysql_imported_db]} postgresql:///#{get_config(:database)} 2>&1"
      log `PGUSER=\"#{get_config(:username)}\" PGPASSWORD=\"#{get_config(:password)}\" PGHOST=\"#{get_config(:host)}\" /tmp/pgloader/build/bin/pgloader --with "prefetch rows = 100" mysql://root@localhost/#{context[:mysql_imported_db]} postgresql:///#{get_config(:database)} 2>&1`

      log "Now moving all tables to public schema"
      tables_to_move = context[:mysql_imported_db_selected_tables] || `#{pg_command} -c "select tablename FROM pg_tables WHERE schemaname = '#{context[:mysql_imported_db]}'; 2>&1`.split("\n")
      tables_to_move.each do |table_to_move|
        # the table names are translated to downcase (by pg migration) if no space is in the name.
        adjusted_table_name = table_to_drop.include?(" ") ? table_to_drop : table_to_drop.downcase

        log "ALTER TABLE \"#{adjusted_table_name}\" SET SCHEMA public;'"
        log `#{pg_command} -c 'ALTER TABLE "#{adjusted_table_name}" SET SCHEMA public;' 2>&1`
      end

      # Remove (now) empty schema
      log "DROP SCHEMA \"#{context[:mysql_imported_db]}\" CASCADE;'"
      log `#{pg_command} -c 'DROP SCHEMA "#{context[:mysql_imported_db]}" CASCADE;' 2>&1`

      success!
    end
  end
end
