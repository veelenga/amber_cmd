require "icr"
require "cli"
require "yaml"
require "colorize"
require "io/console"

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
        arg "msg", desc: "# Short release description", default: "Bumping" 

        string ["-d", "--deploy"], desc: "# Deploy to cloud service: digitalocean | heroku | aws | azure", default: "digitalocean"
      end

      def getsecret(prompt : (String | Nil) = nil)
        puts "#{prompt}:"
        password = STDIN.noecho(&.gets).try(&.chomp)
        puts
        password
      end

      def create_cloud_server(current_version)
        puts "Deploying #{@server_name}"
        puts "Creating docker machine: #{@server_name.colorize(:blue)}"
        do_token = ENV["DOTOKEN"]? || getsecret("DigitalOcean Token")
        `docker-machine create #{@server_name} --driver=digitalocean --digitalocean-access-token=#{do_token}`
        puts "Done creating machine!"
      end

      def remote_cmd(cmd)
        `docker-machine ssh #{server_name} #{cmd}`
      end

      def create_swapfile
        cmds = ["dd if=/dev/zero of=/swapfile bs=2k count=1024k"]
        cmds << "mkswap /swapfile"
        cmds << "chmod 600 /swapfile"
        cmds << "swapon /swapfile"
        remote_cmd(%Q("#{cmds.join(" && ")}"))
        remote_cmd("bash -c \"echo '/swapfile       none    swap    sw      0       0 ' >> /etc/fstab\"")
      end

      def checkout_project
        remote_cmd("apt-get install git")
        puts "please enter repo to deploy from"
        puts "example: https://username:password@github.com/you/project.git"
        repo = ENV["REPO"]? || getsecret("repo:")
        remote_cmd("git clone #{repo} amberproject")
      end

      def deploy_project
        puts "deploying project"
        remote_cmd "docker network create --driver bridge ambernet"
        remote_cmd "docker build -t amberimage amberproject"
        remote_cmd "docker run -it --name amberdb -v db_volume:/var/lib/postgres/data --network=ambernet -e POSTGRES_USER=admin -e POSTGRES_PASSWORD=password -e POSTGRES_DB=crystaldo_development -d postgres"
        remote_cmd "docker run -it --name amberweb -v amberproject:/app/user -p 80:3000 --network=ambernet -e DATABASE_URL=postgres://admin:password@amberdb:5432/crystaldo_development -d amberimage"
        remote_cmd "docker exec -itd amberweb amber migrate up"
        remote_cmd "docker exec -itd amberweb crystal build src/#{project_name}.cr" 
        remote_cmd %Q(docker exec -itd amberweb crystal src/#{project_name}.cr)
      end

      def stop_and_remove
        cmds = ["docker stop amberweb"]
        cmds << "docker rm amberweb"
        # cmds << "docker stop amberdb"
        # cmds << "docker rm amberdb"
        remote_cmd(%Q(bash -c "#{cmds.join(" && ")}"))
      end

      def update_project
        remote_cmd(%Q("cd amberproject && git pull"))
      end

      def release
        new_version = args.version
        message = args.msg
        shard = YAML.parse(File.read("./shard.yml"))
        @project_name = shard["name"].to_s
        version = shard["version"].to_s
        @server_name = "#{project_name}-#{new_version}"

        # files = {
        #   "shard.yml" => "version: #{version}",
        # }
        #
        # files.each do |filename, version_str|
        #   puts "Updating version numbers in #{filename}.".colorize(:light_magenta)
        #   file_string = File.read(filename).gsub(version_str, version_str.gsub(version, new_version))
        #   File.write(filename, file_string)
        # end
        #
        # message = "Bumped version number to v#{new_version}." unless message = ARGV[1]?
        # puts "git commit -am \"#{message}\"".colorize(:yellow)

        # `git add .`
        # `git commit -am "#{message}"`
        # `git push -f`
        #
        # puts "git tag -a v#{new_version} -m \"#{@project_name}: v#{new_version}\"".colorize(:yellow)
        #
        # `git tag -a v#{new_version} -m "#{@name}: v#{new_version}"`
        #
        # puts "git push origin v#{new_version}".colorize(:yellow)
        # `git push origin v#{new_version}`

        # puts "Releasing app #{project_name}-#{new_version}"

        create_cloud_server(new_version)
        create_swapfile
        checkout_project
        deploy_project
        ip = `docker-machine ip #{server_name}`.strip
        puts "ssh root@#{ip} -i ~/.docker/machine/machines/#{server_name}/id_rsa"
        puts "open http://#{ip}"
      end
    end
  end
end
