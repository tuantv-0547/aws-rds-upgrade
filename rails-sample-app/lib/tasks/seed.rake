namespace :seed_data do
  task :article, [:quantity] => :environment do |task, args|
    quantity = args[:quantity].to_i
    puts "\n... Creating #{quantity} articles ..."
    count = 0
    quantity.times do |n|
      Article.create title: "Article title #{n}", description: "Article Description #{n}"
    end
    puts "Created success #{count} articles"
  end
end
