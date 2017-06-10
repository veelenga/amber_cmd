require "cli"
require "shell-table"
require "sentry/sentry_command"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    class Routes < Sentry::SentryCommand
      LABELS         = ["Verb", "Controller", "Action", "Pipeline", "Scope", "Resource"]
      ACTION_MAPPING = {
        "get" => ["index", "show", "new", "edit"],
        "post" => ["create"], "patch" => ["update"],
        "put" => ["update"], "delete" => ["destroy"],
      }

      command_name "routes"
      getter routes = Array(Hash(String, String)).new
      property current_pipe : String?
      property current_scope : String?

      class Help
        caption "# Print out all defined routes in match order, with names"
      end

      def run
        parse_routes
        print_routes_table
      rescue
        puts "Error: Not valid project root directory.".colorize(:red)
        puts "Run `amber routes` in project root directory.".colorize(:light_blue)
        puts "Good bye :("
        exit 1
      end

      private def parse_routes
        File.read_lines("config/routes.cr").each do |line|
          case line.strip
          when .starts_with?("routes")
            set_pipe(line)
          when .starts_with?("resources")
            set_resources(line)
          else
            set_route(line)
          end
        end
      end

      private def set_route(l)
        if md = l.to_s.match(/(\w+)\s+\"([^\"]+)\",\s*(\w+),\s*:(\w+)/)
          return unless ACTION_MAPPING.keys.includes?(md[1]?.to_s)
          route = {"Verb" => md[1]?.to_s}
          route["Controller"] = md[3]?.to_s
          route["Action"] = md[4]?.to_s
          route["Pipeline"] = current_pipe.to_s
          route["Scope"] = current_scope.to_s
          route["Resource"] = md[2]?.to_s
          routes << route
        end
      end

      private def set_resources(l)
        if md = l.to_s.match(/(\w+)\s+\"([^\"]+)\",\s*(\w+)(?:,\s*(\w+)\:\s*\[([^\]]+)\])?/)
          base_route = md[2]?.to_s
          controller = md[3]?.to_s
          filter = md[4]?
          filter_actions = md[5]?.to_s.gsub(/\:|\s/, "").split(",")
          ACTION_MAPPING.each do |verb, v|
            v.each do |action|
              case filter
              when "only"
                next unless filter_actions.includes?(action)
              when "except"
                next if filter_actions.includes?(action)
              end
              route = {"Verb" => verb}
              route["Controller"] = controller
              route["Action"] = action
              route["Pipeline"] = current_pipe.to_s
              route["Scope"] = current_scope.to_s
              route["Resource"] = build_resource(base_route, action, current_scope)
              routes << route
            end
          end
        end
      end

      private def build_resource(route, action, scope)
        route_end = {"show" => ":id", "new" => "new", "edit" => ":id/edit", "update" => ":id", "destroy" => ":id"}
        [scope, route, route_end[action]?].compact.join("/").gsub("//", "/")
      end

      private def set_pipe(l)
        if md = l.to_s.match(/routes\s+\:(\w+)(?:,\s+\"([^\"]+)\")?/)
          @current_pipe = md[1]?
          @current_scope = md[2]?
        end
      end

      private def print_routes_table
        table = ShellTable.new
        table.labels = LABELS
        table.label_color = :light_red
        table.border_color = :dark_gray
        routes.each do |route|
          row = table.add_row
          LABELS.each do |l|
            row.add_column route[l].to_s
          end
        end
        puts table
        exit
      end
    end
  end
end
