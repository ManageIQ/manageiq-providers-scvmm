require 'manageiq/network/port'

module ManageIQ
  module Providers
    module Microsoft
      class Discovery
        MSWIN_PORTS = [
          135, # Microsoft Remote Procedure Call (RPC)
          139  # NetBIOS Session (TCP), Windows File and Printer Sharing
        ].freeze

        SCVMM_PORTS = MSWIN_PORTS + [
          8100 # VMM HTTP Console (WCF)
        ].freeze

        VIRTUAL_SERVER_PORT = 5900 # Microsoft Virtual Machine Remote Control Client

        def self.probe(ost)
          ost.hypervisor << :msvirtualserver if ManageIQ::Network::Port.open?(ost, VIRTUAL_SERVER_PORT)
          ost.hypervisor << :scvmm if ManageIQ::Network::Port.scan_open(ost, SCVMM_PORTS).length == 3
          ost.os << :mswin  if ManageIQ::Network::Port.scan_open(ost, MSWIN_PORTS).length == 2
        end
      end
    end
  end
end
