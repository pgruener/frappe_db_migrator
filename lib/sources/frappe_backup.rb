require 'active_support/all'
require 'active_model'
require './lib/driver_base'
require 'rest-client'

module Sources
  class FrappeBackup < DriverBase
    def initialize(config)
      super

      # init config with defaults (if necessary)
      config.config[:endpoint] ||= get_config(:endpoint, nil, 'https://frappecloud.com')

      # validate config
      if get_config(:username).blank?
        raise "Missing frappe_backup *username* definition for target *#{target_ident}*"
      end

      if get_config(:password).blank?
        raise "Missing frappe_backup *password* definition for target *#{target_ident}*"
      end

      # Only override from possible ENV variables as *get_config* is not designed to return arrays yet, but
      # it's defined as arrays.
      # So as a consequence no defaults may be set for those values if they should be overridable by ENV variables.
      config.config[:include_tables] = get_config(:include_tables)
      config.config[:exclude_tables] = get_config(:exclude_tables)

      if config.config[:include_tables].present?
        config.config[:include_tables] = config.config[:include_tables].split(',').map(&:strip) if config.config[:include_tables].is_a?(String)
      end

      if config.config[:exclude_tables].present?
        config.config[:exclude_tables] = config.config[:exclude_tables].split(',').map(&:strip) if config.config[:exclude_tables].is_a?(String)
      end
    end

    def run!
      # login at frappecloud first and retrieve auth cookie
      url = "#{get_config(:endpoint)}/api/method/login"
      log "Logging in at #{url}"
      response = RestClient.post(url, { usr: get_config(:username), pwd: get_config(:password) })

      if response.code != 200
        log "Error: #{response.code} - #{response.body}"
        return
      end

      session_cookies = response.cookies

      # # get list of backups via http request
      # url = "#{get_config(:endpoint)}/api/method/press.api.site.backups"
      # log "Getting list of backups from #{url}"

      # response = RestClient.post(url, { name: get_config(:site) },
      #                                 { cookies: session_cookies }
      #                           )
      # if response.code != 200
      #   log "Error: #{response.code} - #{response.body}"
      #   return
      # end

      # backups = JSON.parse(response.body).with_indifferent_access[:message] || []

      # if (newest_backup = backups.select { |b| b[:offsite]== 1 }.sort_by { |b| b[:creation] }.last)
      #   log "Got newest backup: #{newest_backup[:name]} (#{newest_backup[:creation]})"
      # else
      #   log "No backups found"
      #   return
      # end

      url = "#{config.get_config(:endpoint)}/api/method/frappe.desk.desk_page.getpage?name=backups"
      log "Getting list of backups from #{url}"

      response = RestClient.get(url, { cookies: session_cookies })
      if response.code != 200
        log "Error: #{response.code} - #{response.body}"
        return
      end

      # log response.body

      backup_url = response.body.scan(/<a href=\\"(\/backups\/[^\\"]+)/).first&.first
      if backup_url.blank?
        log "No backups found"
        return
      end

      database_url = "#{config.get_config(:endpoint)}#{backup_url}"
      database_filename = database_url.split('/').last

      log "Downloading backup from #{database_url}"

      # download backup
      files[:database_backup_path] = "/tmp/#{database_filename}"
      File.open(files[:database_backup_path], 'wb') do |file|
        RestClient.get(database_url, { cookies: session_cookies }) do |response|
          if response.code == 200
            file << response.body
          else
            log "Error: #{response.code} - #{response.body}"
            return
          end
        end
      end

      log "Downloaded to #{files[:database_backup_path]}"

      # unpacking backup file
      log "Unpacking backup file: #{files[:database_backup_path]}"

      log `gzip -d #{files[:database_backup_path]}`

      unpacked_sql_file = files[:database_backup_path].sub(/\.gz$/, '')

      # filter the tables in backup file if configured to do so
      if config.config[:include_tables] || config.config[:exclude_tables]
        context[:mysql_imported_db_selected_tables] = []
        unpacked_sql_tables_folder = "#{unpacked_sql_file}_#{rand(99999)}"
        FileUtils.mkdir_p(unpacked_sql_tables_folder)

        `cd #{unpacked_sql_tables_folder} && csplit -s -ftable #{unpacked_sql_file} "/-- Table structure for table/" {*}`

        FileUtils.rm(unpacked_sql_file) # remove original file, as it will be recreated

        puts "Filtering tables: #{config.config[:include_tables].join(', ')}" if config.config[:include_tables].present?
        log "Filtering tables: #{config.config[:include_tables].join(', ')}" if config.config[:include_tables].present?

        puts "excluded Filtering tables: #{config.config[:exclude_tables].join(', ')}" if config.config[:exclude_tables].present?
        log "excluded Filtering tables: #{config.config[:exclude_tables].join(', ')}" if config.config[:exclude_tables].present?


        files_to_delete = {}
        Dir["#{unpacked_sql_tables_folder}/table*"].sort_by { |l| l }.each do |table_file|
          table_name = `head -n 1 #{table_file}`.sub(/-- Table structure for table \`/, '').sub(/\`/, '').strip or next

          # keep header (first chunk with charset/collation infos, before first splitted table)
          unless table_name.starts_with?('-- Backup generated by')
            if config.config[:include_tables].present?

              unless config.config[:include_tables].detect { |t| table_name =~ /#{t}/ }
                files_to_delete[table_file] = table_name
                next
              end
            end

            if config.config[:exclude_tables].present?

              if config.config[:exclude_tables].detect { |t| table_name =~ /#{t}/ }
                files_to_delete[table_file] = table_name
                next
              end
            end

            context[:mysql_imported_db_selected_tables] << table_name
            log "Keeping table #{table_name} (#{table_file})"
          end

          `cat #{table_file} >> #{unpacked_sql_file}`
        end

        FileUtils.rm_rf(unpacked_sql_tables_folder)
      end

      # import into local mariadb database
      db_name = "import_#{target_ident}_#{rand(99999)}"
      log "Creating database #{db_name}"
      log `mysql -e "CREATE DATABASE #{db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"`
      # log `mysql -e "SET character_set_server='utf8mb4';"`
      # log `mysql -e "SET collation_connection = 'utf8mb4_bin';"`
      # log `mysql -e "SET collation_server = 'utf8mb4_unicode_ci';"`
      log "Importing backup file \"#{unpacked_sql_file}\" into local mariadb database"
      log `mysql #{db_name} < #{unpacked_sql_file}`

      context[:mysql_imported_db_unpacked_file] = unpacked_sql_file
      context[:mysql_imported_db] = db_name

      success!
    end

    def cleanup!
      log "Cleaning up"
      log `rm -f #{context[:mysql_imported_db_unpacked_file]}`

      if context[:mysql_imported_db].present?
        log `mysql -e "DROP DATABASE '#{context[:mysql_imported_db]}';"`
        log "Dropped mysql database #{context[:mysql_imported_db]}"
      end
    end
  end
end
