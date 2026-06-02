# frozen_string_literal: true

class Prog::Vnet::Aws::UpdateFirewallRules < Prog::Base
  subject_is :vm

  def before_run
    pop "firewall rule is added" if vm.destroy_set?
  end

  label def update_firewall_rules
    perms = combine_to_permissions(desired_rules - existing_rules)

    unless perms.empty?
      begin
        aws_client.authorize_security_group_ingress(group_id:, ip_permissions: perms)
      rescue Aws::EC2::Errors::InvalidPermissionDuplicate
      end
    end

    hop_remove_aws_old_rules
  end

  label def remove_aws_old_rules
    perms = combine_to_permissions(existing_rules - desired_rules)

    unless perms.empty?
      begin
        aws_client.revoke_security_group_ingress(group_id:, ip_permissions: perms)
      rescue Aws::EC2::Errors::InvalidPermissionNotFound
      end
    end

    pop "firewall rule is added"
  end

  # Rules the vm should have, as [protocol, from_port, to_port, cidr] tuples
  def desired_rules
    vm.firewall_rules.select(&:port_range).map do |rule|
      [rule.protocol, rule.port_range.begin, rule.port_range.end - 1, rule.cidr.to_s]
    end.uniq
  end

  # Rules currently in the security group, as [protocol, from_port, to_port, cidr] tuples
  def existing_rules
    aws_client.describe_security_groups(group_ids: [group_id]).security_groups.first.ip_permissions.flat_map do |permission|
      (permission.ip_ranges.map(&:cidr_ip) + permission.ipv_6_ranges.map(&:cidr_ipv_6)).map do |cidr|
        [permission.ip_protocol, permission.from_port, permission.to_port, cidr]
      end
    end
  end

  # Collapse tuples into AWS ip_permissions, one entry per protocol/port range so the
  # whole set is applied in a single API call regardless of cidr count
  def combine_to_permissions(rules)
    rules.group_by { |protocol, from_port, to_port, _| [protocol, from_port, to_port] }.map do |(protocol, from_port, to_port), grouped|
      ip6, ip4 = grouped.map(&:last).partition { |cidr| cidr.include?(":") }
      perm = {ip_protocol: protocol, from_port:, to_port:}
      perm[:ip_ranges] = ip4.map { |cidr| {cidr_ip: cidr} } unless ip4.empty?
      perm[:ipv_6_ranges] = ip6.map { |cidr| {cidr_ipv_6: cidr} } unless ip6.empty?
      perm
    end
  end

  def group_id
    @group_id ||= vm.private_subnets.first.private_subnet_aws_resource.security_group_id
  end

  def aws_client
    @aws_client ||= vm.location.location_credential_aws.client
  end
end
