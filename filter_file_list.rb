require 'csv'
require 'json'
require 'optparse'

option = {
    group_by: [],
    filter: [],
    sort_by: [],
}
option_parser = OptionParser.new do |op|
    op.banner = "Usage: #{$0} [options] [csv file...]"
    op.on('-g COLUMN_NAME', '--group-by') do |v|
        option[:group_by] << v
    end
    op.on('-f FILTER', '--filter') do |v|
        option[:filter] << v
    end
    op.on('-s COLUMN_NAME', '--sort_by') do |v|
        option[:sort_by] << v
    end
    op.on('-o PATH', '--output', 'output file path for digests') do |v|
        option[:output] = v
    end
end
option_parser.parse!(ARGV)

mappers = []
option[:filter].map do |filter|
    mapper_factories = {
        'count' => ->(name, operator, value) {
            # the operator must be reversed to swap the left and right operands.
            method = value.to_i.method(operator.tr('<>', '><').intern)
            ->(rows) {method[rows.length] ? rows : []}
        },
        'path' => ->(name, operator, value) {
            method = eval(value).method(operator.intern)
            ->(rows) {rows.filter {|row| method[row[name.intern]]}}
        },
    }
    # Ruby cannot assign matched strings to local variables by (?<>) when patterns contain expression expansion by #{}.
    unless m = /^(#{mapper_factories.keys.join('|')})\s*(?:(==|!=|<=?|>=?|=~|!~)\s*(.*))?$/.match(filter)
        raise ArgumentError.new("wrong filter: filter='#{filter}'")
    end
    mappers << mapper_factories[m[1]][m[1], m[2], m[3]]
end

input_rows = ARGV
    .map {|csv_path| CSV.open(csv_path, converters: :all, headers: true).to_a}
    .flatten(1)
filtered_rows = CSV::Table.new(input_rows)
    .group_by {|row| option[:group_by].map {|column_name| row[column_name]}}
    .values
    .map {|rows| mappers.inject(rows) {|mapped_rows, mapper| mapper[mapped_rows]}}
    .flatten(1)
unless option[:sort_by].empty?
    sequential_number_for_stable_sort = 0
    filtered_rows.sort_by! do |row|
        option[:sort_by]
            .map {|column_name| row[column_name]}
            .append(sequential_number_for_stable_sort += 1)
    end
end

writer = option[:output].nil? ? $stdout : File.open(option[:output], 'w')
writer << CSV::Table.new(filtered_rows).to_csv
writer.close unless option[:output].nil?
