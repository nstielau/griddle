module Griddle
  class Attachment
    
    include Mongo

    def self.attachment_for(options)
      options = self.clean_options(options)
      options_for_search = {:name => options[:name], :owner_type => options[:owner_type], :owner_id => options[:owner_id]}
      record = collection.find_one(options_for_search)
      return new(record) unless record.nil?
      return new(options)
    end

    def self.collection
      @collection ||= Griddle.database.collection('griddle.attachments')
    end
    
    def self.for(name, owner, options = {})
      attachment_for(options.merge({
        :name => name,
        :owner_type => owner.class,
        :owner_id => owner.id
      }))
    end

    def self.valid_attributes
      [:name, :owner_id, :owner_type, :file_name, :file_size, :content_type, :styles, :options]
    end
    #     belongs_to :owner, :polymorphic => true
    
    attr_accessor :attributes

    def initialize(attributes = {})
      @grid = GridFileSystem.new(Griddle.database)
      @attributes = attributes.symbolize_keys
      initialize_processor
      initialize_styles
      create_attachments_for_styles
    end
    
    def assign(uploaded_file)
      if valid_assignment?(uploaded_file)
        self.file = uploaded_file
        self.dirty!
      end
    end
    
    def attributes
      @attributes
    end

    def attributes=(attributes)
      @attributes.merge!(attributes).symbolize_keys
    end

    def collection
      @collection ||= self.class.collection
    end
    
    def destroy
      destroy_file
      collection.remove({:name => name, :owner_type => owner_type, :owner_id => owner_id})
    end
    
    def method_missing(method, *args, &block)
      key = method.to_s.gsub(/\=$/, '').to_sym
      if self.class.valid_attributes.include?(key)
        if key != method
          @attributes[key] = args[0]
        else
          @attributes[key]
        end
      else
        super
      end
    end
    
    def destroy_file
      @grid.delete(grid_key)
      destroy_styles
    end
    
    def dirty?
      @dirty ||= false
      @dirty
    end
    
    def exists?
      Griddle.database['fs.files'].find({'filename' => self.grid_key}).count > 0
    end
    
    def grid_key
      "#{owner_type.tableize}/#{owner_id}/#{name}/#{self.file_name}".downcase
    end

    def tempfile
      if exists?
        tmp = Tempfile.new("griddle_tmp_file")
        tmp << file.read
        tmp.close
        tmp
      end
    end

    def file
      @grid.open(grid_key, 'r') if exists?
    end
    
    def file=(new_file)
      filename = clean_filename(new_file.respond_to?(:original_filename) ? new_file.original_filename : File.basename(new_file.path))
      self.file_name = filename
      self.file_size = File.size(new_file.path)
      self.content_type = new_file.content_type
      @tmp_file = new_file
    end
    
    def name= name
      @attributes[:name] = name.to_sym
    end
    
    def owner_id= id
      @attributes[:owner_id] = id.to_s
    end
    
    def owner_type= str
      @attributes[:owner_type] = str.to_s
    end
    
    def processor
      @processor
    end
    
    def processor= processor
      @attributes[:processor] = processor
      initialize_processor
    end

    def save
      if valid?
        destroy
        save_file
        collection.insert(valid_attributes(@attributes).stringify_keys)
      end
    end
    
    def styles
      @styles
    end
    
    def styles= styles
      @attributes[:styles] = styles
      initialize_styles
    end
    
    def valid?
      dirty? && valid_assignment?(@tmp_file)
    end

    def valid_attributes(attributes)
      Hash[*attributes.select{|key, value| self.class.valid_attributes.include?(key) }.flatten]
    end
    
    protected
    
    def dirty!
      @dirty = true
    end
    
    private
    
    def self.clean_options(options)
      options.symbolize_keys!
      options.merge({
        :name => options[:name].to_sym,
        :owner_type => options[:owner_type].to_s,
        :owner_id => options[:owner_id].to_s
      })
    end
    
    def clean_filename str
      tmp_file_reg = /\.([a-z]{2}[a-z0-9]{0,2})#{Time.now.strftime('%Y%m%d')}-.+/
      str.gsub(tmp_file_reg,'.\1').gsub(/[?:\/*""<>|]+/,'_')
    end
    
    def create_attachments_for_styles
      self.styles.each do |h|
        create_style_attachment h[0]
      end
    end
    
    def create_style_attachment style_name
      raise "Invalid style name :#{style_name}. #{style_name} is a reserved word." if respond_to?(style_name) || !attributes[style_name.to_sym].nil?
      
      attrs = attributes.merge({
        :name => "#{name}/#{style_name}",
        :owner_id => @attributes[:owner_id].to_s,
        :styles => {}
      })
      self.class_eval do
        
        define_method(style_name) do |*args|
          Attachment.attachment_for(attrs)
        end
      
        define_method("#{style_name}=") do |file|
          Attachment.attachment_for(attrs).assign(file)
        end
        
      end
    end
    
    def destroy_styles
      styles.each{|s| send(s[0]).destroy }
    end
    
    def initialize_processor
      @processor = Processor.new @attributes[:processor]
    end
    
    def initialize_styles
      @styles = {} 
      if @attributes[:styles] && @attributes[:styles].is_a?(Hash)
        @styles = @attributes[:styles].inject({}) do |h, value|
          h[value.first.to_sym] = Style.new value.first, value.last, self
          h
        end
      end
    end
    
    def save_file
      @tmp_file.rewind
      @grid.open(grid_key, 'w', :content_type => self.content_type) do |f|
        f.write @tmp_file.read
      end
      save_styles
    end
    
    def save_styles
      styles.each do |h|
        processed_file = processor.process_image(@tmp_file, h[1])
        style_attachment = send(h[0])
        style_attachment.assign(processed_file)
        style_attachment.save
      end
    end
    
    def valid_assignment?(file)
      (file.respond_to?(:original_filename) && file.respond_to?(:content_type))
    end
    
  end
end