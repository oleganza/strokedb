module StrokeDB
  class Store
    def new_doc(slots={})
      Document.new(self,slots)
    end
  end
end