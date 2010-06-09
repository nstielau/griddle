require "test_helper"
require 'digest/md5'
require "models"
include Mongo

class HasAttachmentTest < Test::Unit::TestCase
  context "A Doc that has_grid_attachment :image" do
    setup do
      @document = Doc.new
      @dir = File.dirname(__FILE__) + '/fixtures'
      @image = File.open("#{@dir}/baboon.jpg", 'r')
      @file_system = MongoMapper.database['fs.files']
    end

    teardown do
      @image.close
    end

    context "when not assigned a file" do
      should "should return nil for tempfile" do
        tmp = @document.image.tempfile
        assert_equal(tmp, nil)
      end
    end

    context "when assigned a file" do
      setup do
        @document.image = @image
        @document.save!
      end

      should "should return a Tempfile" do
        tmp = @document.image.tempfile
        assert_equal(tmp.class, Tempfile)
      end

      should "should match original's MD5" do
        tmp = @document.image.tempfile
        tmp_md5 = Digest::MD5.hexdigest(File.read(tmp.path))
        orig_md5 =Digest::MD5.hexdigest(File.read(@image.path))
        assert_equal(tmp_md5, orig_md5)
      end
    end
  end
end