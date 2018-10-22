RSpec.configure do |config|
  config.after(:each, :js) do |example|
    next unless %i[selenium_chrome selenium_chrome_headless].include?(Capybara.current_driver)
    # As of 2018-10-21, traping errors does not work for firefox

    log_only_list = %w[DEBUG INFO]
    log_only_list += %w[WARNING SEVERE ERROR] if example.metadata[:ignore_js_errors]

    errors = []

    page.driver.browser.manage.logs.get(:browser).each do |entry|
      next if entry.message.match?(/Download the React DevTools for a better development experience/)

      log_only_list.include?(entry.level) ? puts(entry.message) : errors << entry.message
    end

    page.driver.browser.manage.logs.get(:driver).each do |entry|
      log_only_list.include?(entry.level) ? puts(entry.message) : errors << entry.message
    end

    raise("Java Script Error(s) on the page:\n\n" + errors.join("\n")) if errors.present?
  end
end
