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
  puts fancy('ActiveRecordQueryTrace.level = :app', color: 32)
  puts fancy('ActiveRecordQueryTrace.lines = 5', color: 32)
  exit
end

lines = File.readlines(path)
total_queries = 0
queries_count_without_save_point = 0
read_queries_count = 0
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
    queries_count_without_save_point += 1 unless query.include?('SAVEPOINT')
    read_queries_count += 1 if query.include?('SELECT')

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
  sql = item[0]
  execution_number = item[1][:count]
  bindings = item[1][:params]

  puts "⚡SQL: #{sql}"
  puts format(
    "\n  Executed: %<count>s (%<percent>s of all queries)",
    count: fancy("#{execution_number} times"),
    percent: fancy("#{((1.0 * execution_number) / total_queries * 100).round(2)}%")
  )

  unless bindings.empty?
    puts "\n  Bindings:"
    bindings.sort_by { |_k, v| v }.reverse.each do |binding_line|
      params, count = binding_line
      puts format('   %<params>s used %<count>s', params:, count: fancy("#{count} times"))
    end
  end

  puts "\n  Occurrences in source:"

  query_traces[item[0]].map { |t| t.join('|') }.tally.sort_by { |_k, v| v }.reverse.each do |t|
    trace_lines = t[0].split('|')
    count = t[1]

    puts format('    %<count>s at:', count: fancy("#{count} occurrences"))
    puts trace_lines

    puts ''
  end

  puts ''
end

puts '----------------------'
puts "Total Queries:\t#{fancy(total_queries)}"
puts '-----'
puts "SAVEPOINTS:\t#{fancy(total_queries - queries_count_without_save_point)}"
puts "Read Queries:\t#{fancy(read_queries_count)}"
puts "Write Queries:\t#{fancy(queries_count_without_save_point - read_queries_count)}"
puts '----------------------'
