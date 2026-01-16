namespace :dev_func do
  desc "Rebuild tables"
  task rebuild: :environment do
    system("rails tmp:clear log:clear")
    system("rails db:drop db:create")
    system("rails db:migrate db:seed")
    system("rails import:management_and_action_pages")
  end

  desc "test app"
  task test_app: :environment do
    system("rspec spec/requests")
  end

  desc "build api"
  task build_api: :environment do
    system("rake rswag:specs:swaggerize")
  end

  desc "check style"
  task check_style: :environment do
    system("rubocop . -a")
  end

  desc "Run code quality tools"
  task code_analysis: :environment do
    system "bundle exec brakeman . -z -q"
    system "bundle exec rubocop . -a"
    system "bundle exec reek app lib spec"
    system "bundle exec rails_best_practices ."
  end
end
