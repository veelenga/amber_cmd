require "cli"
require "shell-table"
require "sentry/sentry_command"

module Amber::CMD
  class MainCommand < Cli::Supercommand

    class Routes < Sentry::SentryCommand
      command_name "routes"
      getter routes = JSON::Any.new("")

      class Help
        caption "# Print out all defined routes in match order, with names"
      end

      def run
        @routes = get_routes
        print_routes_table
      rescue
        puts "Error: Not valid project root directory.".colorize(:red)
        puts "Run `amber routes` in project root directory.".colorize(:light_blue)
        puts "Good bye :("
        exit 1
      end

      private def get_routes
        code = <<-CODE
          require "amber"
          require "./src/controller/*"
          require "./config/*"
          puts Amber::Server.routes.to_json
        CODE
        tmp_file_name = ".#{SecureRandom.urlsafe_base64}.cr"
        tmp_file_path = File.join(Dir.current, tmp_file_name)
        File.write(tmp_file_path, code)
        routes_json = `crystal #{tmp_file_path}`
        File.delete(tmp_file_path)
        JSON.parse(routes_json)
      end

      private def print_routes_table
        table = ShellTable.new
        table.labels = ["Verb", "Controller", "Action", "Scope", "Pipeline", "Resource"]
        table.label_color = :yellow
        table.border_color = :dark_gray
        routes.each do |k, v|
          row = table.add_row
          JSON.parse(v.to_s).each do |_, col|
            row.add_column col.to_s
          end
        end
        puts table
        exit
      end
    end
  end
end
