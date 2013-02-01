# -*- encoding : utf-8 -*-
# == Schema Information
#
# Table name: aix_ports
#
#  id         :integer          not null, primary key
#  port       :string(255)
#  wwpn       :string(255)
#  server_id  :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

require 'spec_helper'

describe AixPort do
  it "has a valid factory" do
    FactoryGirl.create(:aix_port).should be_valid
  end
  it "is invalid without a wwpn" do
    FactoryGirl.build(:aix_port, wwpn: nil).should_not be_valid
  end
  it "is invalid without a port" do
    FactoryGirl.build(:aix_port, port: nil).should_not be_valid
  end
  it "does not allow duplicate wwpn" do
    FactoryGirl.create(:aix_port, wwpn: "0000000C99C0ACA" )
    FactoryGirl.build(:aix_port, wwpn: "0000000C99C0ACA" ).should_not be_valid
  end
  
end
