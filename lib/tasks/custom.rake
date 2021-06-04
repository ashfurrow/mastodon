namespace :custom do
  desc 'Custom task'
  task example: :environment do
    puts 'This is an example task.'
    puts "The database has #{Account.count} users."
  end

  task silence_logs: :environment do
    ActiveRecord::Base.logger = Logger.new('/dev/null')
  end

  desc 'Lookup by IP'
  task :find_by_ip, [:ip] => [:environment, :silence_logs] do |_task, args|
    ip = args[:ip]
    raise 'Specify an IP address in Rake invocation' if ip.nil?

    # You can do this manually this way:
    # ids = User.where(last_sign_in_ip: ip).pluck(:id)
    # accounts = Account.where(id: ids).pluck(:username)

    # Or we can be fancy and user ActiveRecord
    # See docs: https://guides.rubyonrails.org/active_record_querying.html
    Account.joins(:user).where(users: {last_sign_in_ip: ip}).find_each do |account|
      puts account.username
    end
  end

  desc 'Creates report from one account to another'
  task :report_from_to, [:from_username, :reported_username] => [:environment, :silence_logs] do |_task, args|
    from_username = args[:from_username]
    reported_username = args[:reported_username]
    raise 'Need both from and reported fields' if from_username.nil? || reported_username.nil?

    from_account = Account.find_by(username: from_username)
    reported_account = Account.find_by(username: reported_username)
    raise "Cound not find reporting account '#{from_username}' in database." if from_account.nil?
    raise "Cound not find reported account '#{reported_username}' in database." if reported_account.nil?

    ReportService.new.call(
      from_account,
      reported_account,
      comment: 'This report was opened by running a Rake task.'
    )
  end
end
