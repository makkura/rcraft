require 'open3'
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

begin
# Open minecraft
stdin, stdout, stderr, wait_thr = Open3.popen3('java -Xmx1024M -Xms1024M -jar minecraft_server.jar nogui')

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
			puts line	
			case line.strip
				when /\[INFO\] (\w*) .* logged in/i
					player = line.scan /\[INFO\] (\w*) .* logged in/i
					player.flatten!
					player = player[0].to_s
					stdin.puts "tell #{player} Welcome! Cartographer Images at: minecraft.goingasplannedby.us !  !help for command list."
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
							#stdin.puts "tell #{player}  !request"
							#stdin.puts "tell #{player}  !list"
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
