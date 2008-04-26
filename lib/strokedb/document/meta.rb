module StrokeDB
  # Meta is basically a type. Imagine the following document:
  #
  # some_apple:
  #   weight: 3oz
  #   color: green
  #   price: $3
  #
  # Each apple is a fruit and a product in this case (because it has price).
  #
  # we can express it by assigning metas to document like this:
  #
  # some_apple:
  #   meta: [Fruit, Product]
  #   weight: 3oz
  #   color: green
  #   price: $3
  #
  # In document slots metas store references to metadocument.
  #
  # Document class will be extended by modules Fruit and Product.
  module Meta

    class << self
      
      def default_nsurl
        @default_nsurl ||= ""
      end
      
      def default_nsurl=(nsurl)
        @default_nsurl = nsurl
      end
      
      def new(*args, &block)
        mod = Module.new
        args = args.unshift(nil) if args.empty? || args.first.is_a?(Hash)
        args << {} unless args.last.is_a?(Hash)
        mod.module_eval do
          @args = args
          @meta_initialization_procs = []
          @metas = [self]
          extend Meta
          extend Associations
          extend Validations
          extend Coercions
          extend Virtualizations
          extend Util
        end
        mod.module_eval(&block) if block_given?
        mod.module_eval do
          initialize_associations
          initialize_validations
          initialize_coercions
          initialize_virtualizations
        end
        if meta_name = extract_meta_name(*args)
          Object.const_set(meta_name, mod)
        end
        mod
      end

      def document(store=nil)
        raise NoDefaultStoreError.new unless store ||= StrokeDB.default_store
        unless meta_doc = store.find(uuid)
          meta_doc = Document.create!(store, :name => Meta.name, :uuid => uuid, :nsurl => STROKEDB_NSURL)
        end
        meta_doc
      end
      

      private

      def uuid
        @uuid ||= ::Util.sha1_uuid("meta:#{STROKEDB_NSURL}##{Meta.name}")
      end

      def extract_meta_name(*args)
        if args.first.is_a?(Hash)
          args.first[:name]
        else
          args[1][:name] unless args.empty?
        end
      end

    end

    def +(meta)
      if is_a?(Module) && meta.is_a?(Module)
        new_meta = Module.new
        instance_variables.each do |iv|
          new_meta.instance_variable_set(iv, instance_variable_get(iv) ? instance_variable_get(iv).clone : nil)
        end
        new_meta.instance_variable_set(:@metas, @metas.clone)
        new_meta.instance_variable_get(:@metas) << meta
        new_meta.module_eval do
          extend Meta
        end
        new_meta_name = new_meta.instance_variable_get(:@metas).map{|m| m.name}.join('__')
        Object.send(:remove_const, new_meta_name) rescue nil
        Object.const_set(new_meta_name, new_meta)
        new_meta
      elsif is_a?(Document) && meta.is_a?(Document)
        (Document.new(store, self.to_raw.except('uuid','version','previous_version'), true) +
        Document.new(store, meta.to_raw.except('uuid','version','previous_version'), true)).extend(Meta).make_immutable!
      else
        raise "Can't + #{self.class} and #{meta.class}"
      end
    end

    CALLBACKS = %w(on_initialization on_load before_save after_save when_slot_not_found on_new_document on_validation 
      after_validation on_set_slot)

    CALLBACKS.each do |callback_name|
      module_eval %{
        def #{callback_name}(uid=nil, &block)
          add_callback('#{callback_name}', uid, &block)
        end
      }
    end

    def new(*args, &block)
      args = args.clone
      args << {} unless args.last.is_a?(Hash)
      args.last[:meta] = @metas
      doc = Document.new(*args, &block)
      doc
    end

    def create!(*args, &block)
      new(*args, &block).save!
    end
 
    #
    # Finds all documents matching given parameters. The simplest form of
    # +find+ call is without any parameters. This returns all documents
    # belonging to the meta as an array.
    #
    #   User = Meta.new
    #   all_users = User.find
    # 
    # Another form is to find a document by its UUID:
    #
    #   specific_user = User.find("1e3d02cc-0769-4bd8-9113-e033b246b013")
    #
    # If the UUID is not found, nil is returned.
    #
    # Most prominent search uses slot values as criteria:
    #
    #   short_fat_joes = User.find(:name => "joe", :weight => 110, :height => 167)
    # 
    # All matching documents are returned as an array.
    #
    # In all described cases the default store is used. You may also specify
    # another store as the first argument:
    #
    #   all_my_users = User.find(my_store)
    #   all_my_joes  = User.find(my_store, :name => "joe")
    #   oh_my        = User.find(my_store, "1e3d02cc-0769-4bd8-9113-e033b246b013")
    #
    def find(*args)
      if args.empty? || !args.first.respond_to?(:search)
        raise NoDefaultStoreError unless StrokeDB.default_store
        
        args = args.unshift(StrokeDB.default_store) 
      end

      unless args.size == 1 || args.size == 2
        raise ArgumentError, "Invalid arguments for find"
      end

      store = args[0]
      opt = { :meta => @metas.map {|m| m.document(store)} }

      case args[1]
      when String
        raise ArgumentError, "Invalid UUID" unless args[1].match(UUID_RE)

        store.search(opt.merge({ :uuid => args[1] })).first
      when Hash
        store.search opt.merge(args[1])
      when nil
        store.search opt
      else
        raise ArgumentError, "Invalid search criteria for find"
      end
    end

    #
    # Convenient alias for Meta#find.
    #
    alias :all :find

    #
    # Finds the first document matching the given criteria.
    #
    def first(args = {})
      result = find(args)
      result.respond_to?(:first) ? result.first : result
    end

    #
    # Finds the last document matching the given criteria.
    #
    def last(args = {})
      result = find(args)
      result.respond_to?(:last) ? result.last : result
    end

    #
    # Similar to +find+, but creates a document with an appropriate 
    # slot values if document was not found.
    #
    # If found, returned is only the first result.
    #
    def find_or_create(*args, &block)
      result = find(*args)
      result.empty? ? create!(*args, &block) : result.first
    end

    def inspect
      if is_a?(Module)
        name
      else
        pretty_print
      end
    end

    alias :to_s :inspect

    def document(store=nil)
      metadocs = @metas.map do |m|
        @args = m.instance_variable_get(:@args)
        make_document(store)
      end
      metadocs.size > 1 ? metadocs.inject { |a, b| a + b }.make_immutable! : metadocs.first
    end
    
    private

    def make_document(store=nil)
      raise NoDefaultStoreError.new unless store ||= StrokeDB.default_store
      @meta_initialization_procs.each {|proc| proc.call }.clear

      values = @args.clone.select{|a| a.is_a?(Hash) }.first
      values[:meta] = Meta.document(store)
      values[:name] ||= name
      values[:nsurl] ||= Meta.default_nsurl
      values[:uuid] ||= ::Util.sha1_uuid("meta:#{values[:nsurl]}##{values[:name]}") if values[:name]
      
      if meta_doc = find_meta_doc(values, store)
        values[:version] = meta_doc.version
        values[:uuid] = meta_doc.uuid
        args = [store, values]
        meta_doc = updated_meta_doc(args) if changed?(meta_doc, args)
      else
        args = [store, values]
        meta_doc = Document.new(*args)
        meta_doc.extend(Meta)
        meta_doc.save!
      end
      meta_doc
    end

    def find_meta_doc(values, store)
      if uuid = values[:uuid]
        store.find(uuid)
      end
    end

    def changed?(meta_doc, args)
      !(Document.new(*args).to_raw.except('previous_version') == meta_doc.to_raw.except('previous_version'))
    end
    
    def updated_meta_doc(args)
      new_doc = Document.new(*args)
      new_doc.instance_variable_set(:@saved, true)
      new_doc.send!(:update_version!, nil)
      new_doc.save!
    end

    def add_callback(name,uid=nil, &block)
      @callbacks ||= []
      @callbacks << Callback.new(self, name, uid, &block)
    end

    def setup_callbacks(doc)
      return unless @callbacks
      @callbacks.each do |callback|
        doc.callbacks[callback.name] ||= []
        doc.callbacks[callback.name] << callback
      end
    end

  end

end
