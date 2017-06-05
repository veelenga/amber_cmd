require "icr"
require "cli"
require "yaml"
require "colorize"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "r", aliased: "release"

    class Console < Cli::Command
      command_name "release"

      def run
        release
      end

      class Help
        caption "# Starts a Amber console"
      end

      class Options
        arg "version", desc: "# New project version Eg. 1.2.0", required: true
        arg "msg", desc: "# Short release description", required: true

        string ["-d", "--deploy"], desc: "# Deploy to cloud service: digitalocean | heroku | aws | azure", default: "digitalocean"
      end

      def cloud_deploy(app_name, current_version)
         app = "#{app_name}-#{current_version}"
         puts "Deploying #{app}"
         config = YAML.parse(File.read("./.amber.yml"))
         digitalocean = config["digitalocean"]
         puts "Creating docker machine: #{app.colorize(:blue)}"
        `docker-machine create #{app} --driver=digitalocean --digitalocean-access-token=#{digitalocean["token"]}`
         puts "Done creating machine!"
         `docker-machine env #{app}`
      end

      def release
        new_version = args.version
        message = args.msg
        shard = YAML.parse(File.read("./shard.yml"))
        name = shard["name"].to_s
        version = shard["version"].to_s

        files = {
            "shard.yml" => "version: #{version}",
            "src/#{name}/version.cr" => %Q(  VERSION = "#{version})
        }

        files.each do |filename, version_str|
            puts "Updating version numbers in #{filename}.".colorize(:light_magenta)
            file_string = File.read(filename).gsub(version_str, version_str.gsub(version, new_version))
            File.write(filename, file_string)
        end

        message = "Bumped version number to v#{new_version}." unless message = ARGV[1]?
        puts "git commit -am \"#{message}\"".colorize(:yellow)

        `git add .`
        `git commit -am "#{message}"`
        `git push -f`

        puts "git tag -a v#{new_version} -m \"#{name}: v#{new_version}\"".colorize(:yellow)

        `git tag -a v#{new_version} -m "#{name}: v#{new_version}"`

        puts "git push origin v#{new_version}".colorize(:yellow)
        `git push origin v#{new_version}`

        puts "Releasing app #{name}-#{new_version}"

        cloud_deploy(name, new_version)
      end
    end
  end
end
