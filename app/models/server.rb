# -*- encoding : utf-8 -*-
# == Schema Information
#
# Table name: servers
#
#  id            :integer          not null, primary key
#  customer      :string(255)
#  hostname      :string(255)
#  os_type       :string(255)
#  os_version    :string(255)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  sys_fwversion :string(255)
#  sys_serial    :string(255)
#  sys_model     :string(255)
#  global_image  :string(255)
#  install_date  :string(255)
#  run_date      :date
#  nim           :string(255)
#

class Server < ActiveRecord::Base
  has_many :aix_paths, :dependent => :destroy, :autosave => true
  has_many :linux_security_fixes, :dependent => :destroy, :autosave => true
  has_many :health_checks, :dependent => :destroy, :autosave => true
  has_many :volume_groups, :dependent => :destroy, :autosave => true
  has_many :file_systems, :dependent => :destroy, :autosave => true
  has_many :ip_addresses, :dependent => :destroy, :autosave => true
  has_many :server_attributes, :dependent => :destroy, :autosave => true
  has_many :software_deployments
  has_one :lparstat, :dependent => :destroy, :autosave => true
  has_many :softwares, :through => :software_deployments
  has_many :wwpns, :autosave => true
  has_many :san_infras, :through => :wwpns
  accepts_nested_attributes_for :softwares
  belongs_to :hardware
  belongs_to :operating_system_type
  belongs_to :operating_system
  belongs_to :customer
  has_many :activities, as: :trackable, :autosave => true, :dependent => :destroy

  attr_accessible  :hostname, :os_type, :os_version


  # validations
  validates_presence_of :customer_id, :hostname

  validates :hostname, uniqueness: { scope: :customer_id  }

  has_paper_trail :class_name => 'ServerVersion', :ignore => [:run_date]

  # List of attributes we don't want in ransack search
  UNRANSACKABLE_ATTRIBUTES = ["created_at", "updated_at", "hardware_id", "operating_system_id", "operating_system_type_id", "customer_id", "id"]

  # Remove UNRANSACKABLE_ATTRIBUTES from ransack search
  def self.ransackable_attributes auth_object = nil
    (column_names - UNRANSACKABLE_ATTRIBUTES) + _ransackers.keys
  end

  # This return a server count grouped by customer
  # * *Returns* :
  #   - returns a server count by customer
  def self.customers_data
      group(:customer).order("count_hostname DESC").count(:hostname)
  end

  # This return a server count grouped by operating system version
  # * *Returns* :
  #   - returns a server count by system version
  def self.releases_data
    group(:os_version).where(:os_type => "AIX").order("count_hostname DESC").count(:hostname)
  end

  # This return a server count grouped by hardware model
  # * *Returns* :
  #   - returns a server count by hardware version
  def self.sys_models_data
    select("sys_model, count(distinct sys_serial) as count_sys_serial").group(:sys_model).order("count_sys_serial DESC")
  end

  # This method return every servers not found in both fabrics
  # * *Arguments*    :
  #  - *fabric1* -> first fabric which server belongs
  #  - *fabric2* -> second fabric which server should belongs
  # * *Returns* :
  #   - returns every servers belonging to fabric1 but not to fabric2
  def self.not_in_both_fabrics(fabric1, fabric2)
    joins(:san_infras).where('fabric = ?', fabric1) - joins(:san_infras).where('fabric = ?', fabric2)
  end

  # This method return every servers with invalid healthcheck status
  # * *Args*    :
  #  - *check* -> healthcheck service to check
  #  - *status* -> OK status for the helathcheck service
  # * *Returns* :
  #   - returns every servers where healthcheck status is not equals to *status*

  # def self.retrieve_aix_invalid_status(check,status)
  #   joins(:healthchecks).where('healthchecks.check = ?', check)
  #     .where('healthchecks.status != ?', status)
  #     .select('servers.customer, servers.hostname, healthchecks.check as healthcheck, healthchecks.status as status')
  # end

  # This method provides a find method on servers attributes
  # * *Args*    :
  #  - *search* -> search criteria
  # * *Returns* :
  #   - returns every servers where healthcheck status is not equals to *status*

  # def self.aix_alerts_search(search)
  #   joins(:healthchecks).where('servers.customer like :search or servers.hostname like :search or healthchecks.check like :search or healthchecks.status like :search ',
  #     search: search)
  # end

  def add_or_update_attribute(name, value)
    attr = server_attributes.find_or_create_by_name(name)
    attr.update_attributes(output: value, category: "inv")
    attr.activities.find_or_create_by_action("update").touch
  end

  def add_or_update_vg(name, size, free)
    vg = volume_groups.find_or_create_by_name(name)
    vg.update_attributes(vg_size: size, free_size: free)
    vg.activities.find_or_create_by_action("update").touch
  end

  def add_or_update_fs(mount_point, device, size, free)
    fs = file_systems.find_or_create_by_mount_point(mount_point)
    fs.update_attributes(size: size, device: device, free: free)
    fs.activities.find_or_create_by_action("update").touch
  end

  def add_or_update_secfix(name, rhsa, category, severity)
    fix = linux_security_fixes.find_or_create_by_name(name)
    fix.update_attributes(rhsa: rhsa, category: category, severity: severity)
    fix.activities.find_or_create_by_action("update").touch
  end

  def add_or_update_linux_port(name, brand, model, card_type, speed, slot, driver, wwpn, firmware)
    wwn = Wwpn.find_by_wwpn(wwpn)
    if wwn.nil?
      wwn=wwpns.create!(wwpn: wwpn)
    end
    unless wwn.server_id == self.id
      wwpns << wwn
    end

    begin
      wwn.linux_port.update_attributes(name: name, brand: brand, card_model: model, card_type: card_type, speed: speed, slot: slot, driver: driver, firmware: firmware)
    rescue
      wwn.create_linux_port(name: name, brand: brand, card_model: model, card_type: card_type, speed: speed, slot: slot, driver: driver, firmware: firmware)
    end
    wwn.activities.find_or_create_by_action("update").touch
  end

  def add_or_update_aix_port(name, wwpn)
    wwn = Wwpn.find_by_wwpn(wwpn)
    if wwn.nil?
      wwn=wwpns.create!(wwpn: wwpn)
    end

    unless wwn.server_id == self.id
      wwpns << wwn
    end
    begin
      wwn.aix_port.name=name
    rescue
      wwn.create_aix_port(name: name)
    end
    wwn.activities.find_or_create_by_action("update").touch
  end

  def add_or_update_ip_address(address, subnet, mac_address)
    ip = ip_addresses.find_or_create_by_address(address)
    ip.update_attributes(subnet: subnet, mac_address: mac_address)
    ip.activities.find_or_create_by_action("update").touch
  end

  def os_type
    operating_system_type.name
  end

  def os_version
    operating_system.release
  end

  def customer_name
    customer.name
  end
end
