require 'vcr'

module VCRHelpers

  def normalize_cassette_structs(content)
    YAML.load(content).tap do |http_interactions|
      http_interactions.each { |i| normalize_http_interaction(i) }
    end
  end

  def normalize_headers(object)
    object.headers = {} and return if object.headers.nil?
    object.headers = {}.tap do |hash|
      object.headers.each do |key, value|
        hash[key.downcase] = value
      end
    end
  end

  def normalize_http_interaction(i)
    normalize_headers(i.request)
    normalize_headers(i.response)

    i.request.body ||= ''
    i.response.body ||= ''
    i.response.status.message ||= ''

    # Remove non-deterministic headers and headers
    # that get added by a particular HTTP library (but not by others)
    i.response.headers.reject! { |k, v| %w[ server date connection ].include?(k) }
    i.request.headers.reject! { |k, v| %w[ accept user-agent connection expect ].include?(k) }

    # Some HTTP libraries include an extra space ("OK " instead of "OK")
    i.response.status.message = i.response.status.message.strip

    if @scenario_parameters.to_s =~ /excon|faraday/
      # Excon/Faraday do not expose the status message or http version,
      # so we have no way to record these attributes.
      i.response.status.message = nil
      i.response.http_version = nil
    elsif @scenario_parameters.to_s.include?('webmock')
      # WebMock does not expose the HTTP version so we have no way to record it
      i.response.http_version = nil
    end
  end

  def normalize_cassette_content(content)
    return content unless @scenario_parameters.to_s.include?('patron')
    interactions = YAML.load(content)
    interactions.each do |i|
      i.request.headers = (i.request.headers || {}).merge!('Expect' => [''])
    end
    YAML.dump(interactions)
  end

  def modify_file(file_name, orig_text, new_text)
    in_current_dir do
      file = File.read(file_name)
      regex = /#{Regexp.escape(orig_text)}/
      file.should =~ regex

      file = file.gsub(regex, new_text)
      File.open(file_name, 'w') { |f| f.write(file) }
    end
  end
end
World(VCRHelpers)

Given /the following files do not exist:/ do |files|
  check_file_presence(files.raw.map{|file_row| file_row[0]}, false)
end

Given /^the directory "([^"]*)" does not exist$/ do |dir|
  check_directory_presence([dir], false)
end

Given /^a previously recorded cassette file "([^"]*)" with:$/ do |file_name, content|
  write_file(file_name, normalize_cassette_content(content))
end

Given /^(\d+) days have passed since the cassette was recorded$/ do |day_count|
  set_env('DAYS_PASSED', day_count)
end

When /^I modify the file "([^"]*)" to replace "([^"]*)" with "([^"]*)"$/ do |file_name, orig_text, new_text|
  modify_file(file_name, orig_text, new_text)
end

When /^I set the "([^"]*)" environment variable to "([^"]*)"$/ do |var, value|
  set_env(var, value)
end

Then /^the file "([^"]*)" should exist$/ do |file_name|
  check_file_presence([file_name], true)
end

Then /^it should (pass|fail) with "([^"]*)"$/ do |pass_fail, partial_output|
  assert_exit_status_and_partial_output(pass_fail == 'pass', partial_output)
end

Then /^the output should contain each of the following:$/ do |table|
  table.raw.flatten.each do |string|
    assert_partial_output(string, all_output)
  end
end

Then /^the file "([^"]*)" should contain YAML like:$/ do |file_name, expected_content|
  actual_content = in_current_dir { File.read(file_name) }
  normalize_cassette_structs(actual_content).should == normalize_cassette_structs(expected_content)
end

Then /^the file "([^"]*)" should contain each of these:$/ do |file_name, table|
  table.raw.flatten.each do |string|
    check_file_content(file_name, string, true)
  end
end

Then /^the file "([^"]*)" should contain:$/ do |file_name, expected_content|
  check_file_content(file_name, expected_content, true)
end

Then /^the file "([^"]*)" should contain a YAML fragment like:$/ do |file_name, fragment|
  in_current_dir do
    file_content = File.read(file_name)

    # Normalize by removing leading and trailing whitespace...
    file_content = file_content.split("\n").map do |line|
      line.strip
    end.join("\n")

    file_content.should include(fragment)
  end
end

Then /^the cassette "([^"]*)" should have the following response bodies:$/ do |file, table|
  interactions = in_current_dir { YAML.load_file(file) }
  actual_response_bodies = interactions.map { |i| i.response.body }
  expected_response_bodies = table.raw.flatten
  actual_response_bodies.should =~ expected_response_bodies
end

