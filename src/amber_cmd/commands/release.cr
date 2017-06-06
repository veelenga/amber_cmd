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
      property project_name : String?

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

      def remote_cmd(cmd)
        `docker-docker ssh #{server_name} #{cmd}`
      end

      def create_swapfile
        cmds = ["dd if=/dev/zero of=/swapfile bs=2k count=1024k"]
        cmds << "chmod 600 /swapfile"
        cmds << "mkswap /swapfile"
        cmds << "swapon /swapfile"
        cmds << "bash -c \"echo '/swapfile       none    swap    sw      0       0 ' >> /etc/fstab\""
        remote_cmd(cmds.join(" && "))
      end

      def checkout_project
        remote_cmd("apt-get install git")
        puts "please enter repo to deploy from" 
        puts "example: https://username:password@github.com/you/project.git"
        repo = gets.strip
        remote_cmd("git clone #{repo}")
      end

      def update_project
        remote_cmd(%Q("cd #{project_name} && git pull"))
      end

      def release
        new_version = args.version
        message = args.msg
        shard = YAML.parse(File.read("./shard.yml"))
        @project_name = shard["name"].to_s
        version = shard["version"].to_s
        @server_name = "#{project_name}-#{current_version}"

        files = {
          "shard.yml" => "version: #{version}"
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
        checkout_project
        `docker-compose up -f production -d`
      end
    end
  end
end
