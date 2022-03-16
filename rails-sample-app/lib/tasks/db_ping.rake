namespace :db do
  task :ping, [] => :environment do
    downtime_start_at = nil
    downtime_end_at = nil

    is_dead = false

    while true
      begin
        if Article.count
          if is_dead
            downtime_end_at = Time.zone.now
            break
          end

          puts "Alive"
          sleep 1
        end
      rescue StandardError
        begin
          if downtime_start_at.nil?
            downtime_start_at = Time.zone.now
            is_dead = true
          end

          ActiveRecord::Base.connection.reconnect!
        rescue
          puts "Dead"
          sleep 3
        end
      end
    end

    puts "Downtime duration: #{downtime_end_at - downtime_start_at}s"
  end
end
