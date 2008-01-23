module StrokeDB
  class SkiplistStore < Store
    attr_accessor :chunk_storage

    def initialize(chunk_storage)
      @chunk_storage = chunk_storage
    end
    
    def find(uuid, version=nil)
      # TODO: master chunk scanning
      @chunk_storage.each do |chunk|
        doc = chunk.find(uuid)
        return doc if doc
      end
    end

    def exists?(uuid)
      # TODO: master chunk scanning
      !!find(uuid)
    end

    def last_version(uuid)
      # TODO: dunno
    end

    def save!(doc)
      mychunk = nil
      # determine a chunk where to insert
      @chunk_storage.each do |chunk|
        # later chunk
        if doc.uuid < chunk.uuid
          if mychunk
            break
          else
            # actually, the first chunk, so use it:
            # will insert in the head 
            mychunk = chunk 
            break
          end
        else # >=
          mychunk = chunk
        end
      end
      
      # insert to mychunk
      cur_chunk, new_chunk = mychunk.insert(uuid, doc)
      [cur_chunk, new_chunk].compact.each do |chunk|
        @chunk_storage.save!(chunk)
      end

    end

  end
end