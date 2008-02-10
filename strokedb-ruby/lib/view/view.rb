module StrokeDB
  View = Meta.new do
    attr_accessor :map_with_proc
    attr_reader :reduce_with_proc
    on_initialization do |view, block|
      view.map_with_proc = block || proc {|doc, *args| doc }
    end

    def reduce_with(&block)
      @reduce_with_proc = block
      self
    end

    def emit(*args) 
      ViewCut.new(store, :view => self, :args => args, :lamport_timestamp_state => 0).emit
    end

  end
  ViewCut = Meta.new do
    on_initialization do |cut|
      if cut.new?
        cut.instance_eval do
          @map_with_proc = view.map_with_proc
          @reduce_with_proc = view.reduce_with_proc
        end
      end
    end
    def emit
      mapped = []
      store.each(:after_lamport_timestamp => lamport_timestamp_state) {|doc| mapped << @map_with_proc.call(doc,*args) }
      documents = (@reduce_with_proc ? mapped.select {|doc| @reduce_with_proc.call(doc,*args) } : mapped).map{|d| d.extend(VersionedDocument)}
      ViewCut.new(store, :documents => documents, :view => view, :args => args, :lamport_timestamp_state => store.lamport_timestamp)
    end
    def to_a
      documents
    end
  end
end