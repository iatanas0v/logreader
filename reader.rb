# frozen_string_literal: true

require 'io/console'

def fancy(str, color: 35)
  "[0m[1;#{color}m#{str}[0m"
end

path = ARGV[0]

if path == '--help'
  puts 'Make sure you have the following snippet before your test code:'
  puts ''
  puts fancy(
    "if ActiveSupport::Subscriber.subscribers.last.class.name != 'ActiveRecordQueryTrace::CustomLogSubscriber'",
    color: 32
  )
  puts fancy('  ActiveRecordQueryTrace::CustomLogSubscriber.attach_to :active_record', color: 32)
  puts fancy('  ActiveRecordQueryTrace.enabled = true', color: 32)
  puts fancy('end', color: 32)
  exit
end

lines = File.readlines(path)
total_queries = 0
grouped_queries = {}
query_traces = {}
last_query = nil

lines.each do |line|
  is_root = line.match?(/^\d{4}-\d{2}-\d{2}/) || line.start_with?('/home/ivan/')
  is_query = line.include?('ActiveRecord')
  is_query_line_with_sql = is_query && line.include?(':sql')
  is_stack_trace = !is_query_line_with_sql && line.start_with?('/home/ivan/')

  next if (is_root && !is_query_line_with_sql) || is_stack_trace

  if is_root
    # Extract SQL only
    line = line.match(/:sql.+?=> (.+?):allocations/)[1]
    # Clean it up a bit
    line = line.gsub('\"', '')

    # Just query
    last_query = query = line.match(/(.*?), :binds/)&.to_a&.at(1) || line
    params = line.match(/.*?:binds.+?=>(.+}),/)&.to_a&.at(1)

    # Start new trace
    query_traces[last_query] = [] unless query_traces.key?(last_query)
    query_traces[last_query].push([])

    total_queries += 1

    grouped_queries[query] = { count: 0, params: {} } unless grouped_queries.key?(query)
    grouped_queries[query][:count] += 1
    if params
      grouped_queries[query][:params][params] = 0 unless grouped_queries[query][:params].key?(params)
      grouped_queries[query][:params][params] += 1
    end
  elsif last_query
    # Query stack line
    query_traces[last_query].last.push(line)
  end
end

puts '------------------------------'

# Print report
grouped_queries.sort_by { |_k, v| v[:count] }.each do |item|
  next if item[1][:count] == 1

  puts "⚡ #{item[0]}"
  puts 'Executed: ' + fancy("#{item[1][:count]} times")
  puts 'Params:'
  item[1][:params].sort_by { |_k, v| v }.reverse.each do |p|
    puts "#{p[0]} used " + fancy("#{p[1]} times")
  end

  puts 'Trances:'

  query_traces[item[0]].map { |t| t.join('|') }.tally.sort_by { |_k, v| v }.reverse.each do |t|
    trace_lines = t[0].split('|')
    count = t[1]

    puts '   Happened ' + fancy("#{count} times")
    puts trace_lines
    puts '   ---------------------------'
  end

  puts "\n"
end

puts "\n"

puts '------------------------------'
puts "---   Total Queries: #{fancy(total_queries)}   ---"
puts '------------------------------'
