class Upload < ActiveRecord::Base
  include Workflow
  attr_accessible :upload, :import_type, :workflow_state
  has_attached_file :upload
  has_one :import_log, :dependent => :destroy
  
  TYPES = %w[server san sod]

  workflow do
    state :new do
      event :uploading, :transition_to => :uploaded
    end
    state :uploaded do
      event :processing, :transition_to => :importing
    end

    state :importing do
      event :success, :transition_to => :processed
      event :error, :transition_to => :failed
    end

    state :processed
    state :failed
  end

  def processing
    case import_type
      when 'server'
        server_import
      when 'san'
        san_import
      when 'sod'
        sod_import
    end
  end
  
  def server_import
    import_log = self.build_import_log
    import_log.success_count=0
    import_log.error_count=0
    import_log.save
    import_log.content = "starting importing #{self.upload_file_name}\n"
    unless self.csv_file_content?
      import_log.content << "ERROR: not a csv file\n"
      import_log.result = failed
      import_log.save
      return false
    end

    total_chunks = SmarterCSV.process(self.upload.path, :chunk_size => 500, :col_sep => "\t", :key_mapping => { :scm_manager=> nil, :scm_alias => nil }) do |chunk|
      Server.transaction do
        chunk.each do |entry|
          if entry[:lparstat].nil?
            import_log.error_count += 1
            next
          end
          next unless entry[:version] == "1.8".to_f
          imported_server = ServerImport.new(entry)
          begin 
            imported_server.save!
            imported_server.save_softwares!
          rescue  Exception => e
            import_log.error_count += 1
            import_log.content << "SAVE ERROR: #{e.message}\n"
            import_log.content << imported_server.to_yaml
          else
            import_log.success_count += 1
          end

          begin 
            imported_server.save_softwares!
          rescue  Exception => e
            import_log.error_count += 1
            import_log.content << "SOFT SAVE ERROR: #{e.message}\n"
            import_log.content << imported_server.softwares.to_yaml
          else
            import_log.success_count += 1
          end
        end
      end
    end
    import_log.save
  end
  #handle_asynchronously :server_import

  def san_import

  end
  handle_asynchronously :san_import

  def sod_import

  end
  handle_asynchronously :sod_import  

  def csv_file_content?
    if upload_content_type.match(/csv/)
      return true
    else
      return false
    end
  end

end
