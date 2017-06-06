require "icr"
require "cli"
require "yaml"
require "colorize"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "r", aliased: "release"

    class Console < Cli::Command
      command_name "release"
      property server_name : String?

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

      def create_cloud_server(app_name, current_version)
        puts "Deploying #{@server_name}"
        config = YAML.parse(File.read("./.amber.yml"))
        digitalocean = config["digitalocean"]
        puts "Creating docker machine: #{@server_name.colorize(:blue)}"
        `docker-machine create #{@server_name} --driver=digitalocean --digitalocean-access-token=#{digitalocean["token"]}`
        puts "Done creating machine!"
        `docker-machine env #{@server_name}`
      end

      def create_swapfile
        docker-machine ssh docker-crystal1 "dd if=/dev/zero of=/swapfile bs=2k count=1024k && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && bash -c \"echo '/swapfile       none    swap    sw      0       0 ' >> /etc/fstab\""
      end

      def release
        new_version = args.version
        message = args.msg
        shard = YAML.parse(File.read("./shard.yml"))
        name = shard["name"].to_s
        version = shard["version"].to_s
        @server_name = "#{app_name}-#{current_version}"

        files = {
          "shard.yml"              => "version: #{version}",
          "src/#{name}/version.cr" => %Q(  VERSION = "#{version}),
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
        add_swapfile
      end
    end
  end
end
