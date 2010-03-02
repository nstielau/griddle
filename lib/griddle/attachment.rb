module Griddle
  class Attachment
    include MongoMapper::Document
    
    belongs_to :owner, :polymorphic => true
    key :name, String
    key :owner_id, ObjectId, :required => true
    key :owner_type, String, :required => true
    key :file_name, String
    key :file_size, Integer
    key :content_type, String
    
    before_destroy :destroy_file
    
    def initialize(name, owner)
      @name = name
      @owner_type = owner.class.to_s
      @owner_id = owner.id
    end
    
    def grid_key
      @grid_key ||= "#{owner_type.pluralize}/#{owner_id}/#{name}/#{file_name}"
    end
    
    def assign(uploaded_file)
      return nil unless valid_assignment?(uploaded_file)
      self.file = uploaded_file
    end
    
    def file=(new_file)
      file_name = new_file.respond_to?(:original_filename) ? new_file.original_filename : File.basename(new_file.path)
      self.file_name = file_name
      self.file_size = File.size(new_file)
      self.content_type = new_file.content_type
      
      GridFS::GridStore.open(self.class.database, grid_key, 'w', :content_type => self.content_type) do |f|
        f.write new_file.read
      end
    end
    
    def file
      GridFS::GridStore.new(self.class.database, grid_key, 'r') unless file_name.blank?
    end
    
    def destroy_file
      GridFS::GridStore.unlink(self.class.database, grid_key)
    end
    
    private
    
    def valid_assignment?(file)
      file.nil? || (file.respond_to?(:original_filename) && file.respond_to?(:content_type))
    end
    
  end
end