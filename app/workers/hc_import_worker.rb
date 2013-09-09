require "clockwork"

class HcImportWorker
  include Sidekiq::Worker

  def hcm_json(filename)
      f=File.open(filename, 'r')
      json = JSON.load(f)
      f.close()

      json['CHECKS'].each do |x|
        puts x['SERVER']

        srv = Server.find_or_create_by_name(:name => x['SERVER'])
        srv.customer=json['CUSTOMER']

        x['RESULTS'].each do |y|
            hc = srv.health_checks.select{|h| h.name==y['PLUG']}.first
            if hc.nil?
                srv.health_checks.append(HealthCheck.new(:name=>y['PLUG'], :description=>y['DESCRIPTION'], :output=>y['OUTPUT'], :return_code=>y['CODE'], :info=>y['INFO'], :hc_errors=>''))
            else
                hc.update_attributes(:output=>y['OUTPUT'], :description=>y['DESCRIPTION'], :return_code=>y['CODE'].to_i,:info=>y['INFO'], :hc_errors=>'')
            end
        end
        begin
          srv.save!
        rescue Exception => e
            puts "ERROR: unable to save SRV : #{e.message}"
        end
      end
    end


  def perform
    puts Rails.root
    new_path=Rails.root.join('import', 'hcm', 'new').to_s
    done_path=Rails.root.join('import','hcm', 'imported').to_s
    files = Dir.entries(new_path).select{|x| x.end_with?("json")}
    files.each do |x|

    hcm_json([new_path,x].join('/'))
    File.rename([new_path,x].join('/'), [done_path,x+Time.new.to_s.gsub(' ','-')].join('/'))
    end
  end

end
