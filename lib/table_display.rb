module TableDisplay
  def to_table(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    extra_methods = args.length > 0 ? args.collect(&:to_s) : []
    extra_methods += Array(options.delete(:methods)) if options[:methods]
    only_attributes = Array(options.delete(:only)) if options[:only]
    only_attributes ||= [] if args.length > 0
    except_attributes = Array(options.delete(:except)) if options[:except]
    except_attributes = (except_attributes + except_attributes.collect(&:to_s)).uniq if except_attributes.present? # we have to keep string and symbol arguments separate for hashes, which may not have 'indifferent access'
    display_inspect = options.nil? || !options.has_key?(:inspect) || options.delete(:inspect)
    raise "unknown options passed to to_table: #{options.keys.to_sentence}" unless options.blank?
    
    column_lengths = ActiveSupport::OrderedHash.new
    
    data = []
    if only_attributes
      # we've been given an explicit list of attributes to display
      only_attributes.each {|attribute| column_lengths[attribute] = 0}
    else
      # find all the attribute names
      each do |record|
        next if record.nil?
      
        # ActiveRecord's #attributes implementation iterates over #attribute_names adding a duped value to the output hash for each entry, so
        # it's actually more expensive to get the keys and values in one go using #attributes than it is for us to work off #attribute_names ourselves.
        if record.respond_to?(:attribute_names)
          # an ActiveModel instance
          attribute_names = record.attribute_names
        elsif Object.const_defined?(:OpenStruct) && record.is_a?(OpenStruct)
          # OpenStruct has a crappy API, #inspect will show the attributes but there's no public way to get a list of them!
          record = record.instance_variable_get("@table")
          attribute_names = record.keys
        elsif record.respond_to?(:attributes)
          # something like an ActiveResource, which doesn't implement attribute_names but does implement attributes
          attribute_names = record.attributes.keys
        else
          # hopefully something like a hash
          attribute_names = record.keys
        end
      
        if attribute_names.any? {|name| column_lengths[name].nil?} # optimisation, in most use cases all records will have the same type and the same attributes, so we needn't run this for each - but we do handle varying attribute lists, and attributes that are not columns on the model (calculated columns etc.)
          # for ActiveRecord classes, we look at the .columns explicitly so we can keep them in the right order
          columns_to_check = record.is_a?(ActiveRecord::Base) ? ((record.class.columns.collect(&:name) & attribute_names) + attribute_names).uniq : attribute_names
          columns_to_check.each do |name|
            next if (only_attributes && !only_attributes.include?(name)) || (except_attributes && except_attributes.include?(name))
            column_lengths[name] = 0 # the values of columns are the maximum width of value seen; when we come to print out, if the max seen is zero then the attribute has never actually been seen (eg. when a find(:all, :select => ...) has been used to exclude some of the database columns from the resultset), and we hide the column.
          end
        end
      end
    end

    # also add any :methods given to the list
    extra_methods.each {|name| column_lengths[name] = 0}
    
    each do |record|
      # add the values for all the columns in our list in order they are
      data << column_lengths.collect do |attribute, max_width|
        value = record.is_a?(Hash) ? record[attribute] : record.send(attribute)
        string_value = display_inspect ? value.inspect : (value.is_a?(String) ? value : value.to_s)
        column_lengths[attribute] = string_value.mb_chars.length if string_value.mb_chars.length > max_width
        value.is_a?(Numeric) ? value : string_value # keep Numeric values as-is for now, so we can handle them specially in the output below
      end
    end
    
    return [] if data.empty?
    
    # build the table header
    separator_string = "+"
    heading_string   = "|"
    column_lengths.each do |attribute, max_width|
      next unless max_width > 0 # skip any columns we never actually saw
      name = attribute.to_s
      
      # the column needs to fit the column header as well as the values
      if name.mb_chars.length > max_width
        column_lengths[attribute] = max_width = name.mb_chars.length
      end
      
      separator_string << '-'*(max_width + 2) << '+'
      heading_string   << ' ' << name.ljust(max_width) << ' |'
    end
    
    rows = [separator_string, heading_string, separator_string]
    data.each do |data_row|
      data_string = "|"
      column_lengths.each_with_index do |(attribute, max_width), index|
        next unless max_width > 0 # skip any columns we never actually saw
        value = data_row[index]
        if value.is_a?(Numeric)
          data_string << ' ' << (display_inspect ? value.inspect : value.to_s).mb_chars.rjust(max_width) << ' |'
        else
          data_string << ' ' << value.mb_chars.ljust(max_width) << ' |'
        end
      end
      rows << data_string
    end
    rows << separator_string
  end
end

module Kernel
  def pt(target, *options)
    puts target.to_table(*options)
  end
end

# all Enumerable classes should get TableDisplay functionality...
Enumerable.send(:include, TableDisplay)

# including those that have already included Enumerable by the time this plugin is loaded.
# Ruby doesn't recursively update through the module tree, so although any new classes/modules
# that include Enumerable will get TableDisplay, we have to do it ourself for older ones.
ObjectSpace.each_object(Module) {|o| o.send(:include, TableDisplay) if o.ancestors.include?(Enumerable)}
ObjectSpace.each_object(Class)  {|o| o.send(:include, TableDisplay) if o.ancestors.include?(Enumerable)}
