require 'open3'
require 'yaml'
require 'logger'

# Additions to built in modules / classes to make life easier

module Process
    # Method to determine running process from tonystubblebine
    # via: http://stackoverflow.com/questions/325082/how-can-i-check-from-ruby-whether-a-process-with-a-certain-pid-is-running
    def self.running?(pid)
        begin
            Process.kill(0, pid)
            true
        rescue Errno::ESRCH
            false
        end
    end
end

class String
    def is_numeric?
         Float self rescue false # Short and sweet since an actual value does evaluate true
    end
end

# Let the actual process get started!

begin

# Load up the config file
    config = YAML.load_file("config.yml")
    server = config["server"] || "java -Xmx1024M -Xms1024M -jar minecraft_server.jar nogui"
    welcome_msg = config["welcome"] || ""
    log_file = config["logfile"] || "minecraft.log"
    log_frequency = config["logfrequency"] || "monthly"

    # Set up a log
    log = Logger.new(log_file, shift_age="#{log_frequency}" )

    # Load the item list
    item_list = YAML.load_file("itemlist.yml")
    item_keys = item_list.keys
    
    # Load the kit list
    kit_list = YAML.load_file("kits.yml")
    
    # Open minecraft
    stdin, stdout, stderr, wait_thr = Open3.popen3(server)

    # Grab process id's to watch all the threads
    mc_pid = wait_thr[:pid]
    parent_pid = Process.pid
    out_reader = Process.fork
    err_reader = Process.fork unless out_reader.nil?
    own_pid = Process.pid

    while(true) # Always, like sasquatch
        # Child 1: Reads and posts STDOUT of mc
        if out_reader.nil?
            if !Process.running?(mc_pid)
                puts "Out_Reader: Exiting"
            Process.exit!
            end

            stdout.each_line do |line|
                puts line
            end
            sleep 1
        end

        # Child 2: reads and posts stderr of mc
        if !out_reader.nil? and err_reader.nil?
            if !Process.running?(mc_pid)
                puts "Err_Reader: Exiting"
            Process.exit!
            end

            stderr.each_line do |line|
                line.strip!
                puts line

                # Log if it is chat or user commands
                if line =~ /\[INFO\] <\w*>/
                    log.info ((line.scan /\[INFO\] (<\w*>.*)/).flatten.shift)
                end
                case line
                when /\[INFO\] (\w*) .* logged in/i
                    player = line.scan /\[INFO\] (\w*) .* logged in/i
                    player.flatten!
                    player = player[0].to_s
                    stdin.puts "tell #{player} #{welcome_msg}"
                when /\[INFO\] <(\w*)> (!.*)$/i  # Player input
                    command = line.scan /\[INFO\] <(\w*)> (!.*)$/i
                    command.flatten!
                    puts "Command: #{command}"
                    player = command.shift
                    request = command.shift
                    puts "Player: #{player} :: Request: #{request}"
                    case request
                    when /!help$/i
                        stdin.puts "tell #{player} Available commands include: "
                        stdin.puts "tell #{player}  !help"
                        stdin.puts "tell #{player}  !request quanity item"
                        stdin.puts "tell #{player}  !list item name"
                        stdin.puts "tell #{player}  !kit kitname"
                        stdin.puts "tell #{player}  !kits"
                    when /!request (.*)$/i
                        # !request <quantity> <item>
                        # If no quantity, assume 1
                        # Item request found, evaluate the request
                        item_request = request.scan /!request (\d*) (.*)$/i
                        item_request.flatten!
                        if item_request.empty?
                        	# No quantity listed, insert one
                        	request.insert(8, " 1 ")
                        	item_request = request.scan /!request (\d*) (.*)$/i
                        	item_request.flatten!
                        end
                        puts "Request: #{item_request}"
                        quantity = item_request.shift
                        item = item_request.shift
                        item.strip!
                        # match casing with the item list
                        #item.gsub!(/^[a-z]|\s+[a-z]/) { |a| a.upcase }
						item.upcase!

                        if item_list.include? item
                            (quantity.to_i/64).times do
                                stdin.puts "give #{player} #{item_list[item]} 64"
                            end
                            if (quantity.to_i % 64) > 0
                                stdin.puts "give #{player} #{item_list[item]} #{quantity.to_i % 64}"
                            end
                        else
                            if item.is_numeric?
                                (quantity.to_i/64).times do
                                    stdin.puts "give #{player} #{item} 64"
                                end
                                if (quantity.to_i % 64) > 0
                                    stdin.puts "give #{player} #{item} #{quantity.to_i % 64}"
                                end
                            else
                                stdin.puts "tell #{player} #{item} not found"
                            end
                        end
                    when /!kit (.*)$/i
                    	kit_request = request.scan /!kit (.*)$/i
                    	kit_request.flatten!
                    	kit = kit_request.shift
                    	puts "Kit Request: #{kit}"
                    	
                    	kit.upcase!
                    	if kit_list.include? kit
                    		kit_list[kit].each do |sub_item|
                    			sub_item.each_pair do |key, value|
                    				stdin.puts "give #{player} #{item_list[key]} #{value[0].to_i}"
                    			end
                    		end
                    	end
                    when /!kits$/i
                    	stdin.puts "tell #{player} Possible Kits are:"
                    	kit_list.keys.each do |kit|	
							stdin.puts "tell #{player} -#{kit} "
						end
                    when /!item (.*)$/i
                        item_inquery = request.scan /!item (.*)$/i
                        item_inquery.flatten!
                        item = item_inquery.shift
                        puts "Inquery: #{item}"
                        #item.gsub!(/^[a-z]|\s+[a-z]/) { |a| a.upcase }
                        item.upcase!
                        stdin.puts "tell #{player} Possible items are:"
                        item_keys.each do |key|
                            stdin.puts "tell #{player} #{key}" unless !key.include? item
                        end
                    else
                    #do nothing
                    end
                else
                #do nothing
                end
            end
            sleep 1
        end

        # Parent: Reads STDIN and pushes it to mc
        if !out_reader.nil? and !err_reader.nil?
            input = gets.chomp
            if !input.empty?
                if input.downcase.include? "exit"
                    raise "SIGTERM"
                end
            stdin.puts input
            end
        end
    end
rescue Exception => e

    puts e.message == "SIGTERM" ? (own_pid == parent_pid ? "Preparing to exit." : "" )  : "Error: #{e}"
    # Parent should be responsible for killing everything
    Process.kill(15, out_reader) unless own_pid != parent_pid or !Process.running?(out_reader)
    Process.kill(15, err_reader) unless own_pid != parent_pid or !Process.running?(err_reader)
    # Attempt a clean close if possible
    if Process.running?(mc_pid) and own_pid == parent_pid
        puts "Stopping minecraft_server"
        wait_time = 15
        (wait_time.to_i / 5).times do |loop_number|
            # loop number starts at 0 rather than 1
            stdin.puts "say Server is going down in #{(wait_time.to_i) - (loop_number * 5) }s"
            sleep 5
        end
        stdin.puts "stop"
        sleep 5
        # Give it a chance to stop normally
        if Process.running?(mc_pid)
            stdin.close
            stdout.close
            stderr.close
            wait_thr.close
        end
    end
    Process.exit!
end
