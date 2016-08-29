# -*- encoding: utf-8 -*-
#
# Author:: Simon McCartney <simon.mccartney@hp.com>
#
# Copyright (C) 2013, Chris Lundquist, Simon McCartney
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen/provisioner/base'
require 'kitchen-salt/util'
require 'kitchen-salt/prepare'
require 'yaml'

module Kitchen
  module Provisioner
    # Basic Salt Masterless Provisioner, based on work by
    #
    # @author Chris Lundquist (<chris.ludnquist@github.com>)

    class SaltSolo < Base
      include Kitchen::Salt::Util
      include Kitchen::Salt::Prepare

      default_config :salt_version, 'latest'

      # supported install methods: bootstrap|apt
      default_config :salt_install, 'bootstrap'

      default_config :salt_bootstrap_url, 'http://bootstrap.saltstack.org'
      default_config :salt_bootstrap_options, ''

      # alternative method of installing salt
      default_config :salt_apt_repo, 'http://apt.mccartney.ie'
      default_config :salt_apt_repo_key, 'http://apt.mccartney.ie/KEY'
      default_config :salt_ppa, 'ppa:saltstack/salt'

      default_config :chef_bootstrap_url, 'https://www.getchef.com/chef/install.sh'

      default_config :salt_config, '/etc/salt'
      default_config :salt_minion_config, '/etc/salt/minion'
      default_config :salt_env, 'base'
      default_config :salt_file_root, '/srv/salt'
      default_config :salt_pillar_root, '/srv/pillar'
      default_config :salt_state_top, '/srv/salt/top.sls'
      default_config :state_collection, false
      default_config :state_top, {}
      default_config :state_top_from_file, false
      default_config :salt_run_highstate, true
      default_config :salt_copy_filter, []
      default_config :is_file_root, false
      default_config :require_chef, true

      default_config :dependencies, []
      default_config :vendor_path, nil
      default_config :omnibus_cachier, false

      # salt-call version that supports the undocumented --retcode-passthrough command
      RETCODE_VERSION = '0.17.5'.freeze

      def install_command
        debug(diagnose)

        # if salt_verison is set, bootstrap is being used & bootstrap_options is empty,
        # set the bootstrap_options string to git install the requested version
        if (config[:salt_version] != 'latest') && (config[:salt_install] == 'bootstrap') && config[:salt_bootstrap_options].empty?
          debug("Using bootstrap git to install #{config[:salt_version]}")
          config[:salt_bootstrap_options] = "-P git v#{config[:salt_version]}"
        end

        salt_install = config[:salt_install]

        salt_url = config[:salt_bootstrap_url]
        bootstrap_options = config[:salt_bootstrap_options]

        salt_version = config[:salt_version]
        salt_apt_repo = config[:salt_apt_repo]
        salt_apt_repo_key = config[:salt_apt_repo_key]
        salt_ppa = config[:salt_ppa]

        <<-INSTALL
          sh -c '
          #{Util.shell_helpers}

          # what version of salt is installed?
          SALT_VERSION=`salt-call --version | cut -d " " -f 2`


          if [ -z "${SALT_VERSION}" -a "#{salt_install}" = "bootstrap" ]
          then
            do_download #{salt_url} /tmp/bootstrap-salt.sh
            #{sudo('sh')} /tmp/bootstrap-salt.sh #{bootstrap_options}
          elif [ -z "${SALT_VERSION}" -a "#{salt_install}" = "apt" ]
          then
            if [ -z "`which lsb_release`" ]; then
              . /etc/lsb-release
            else
              DISTRIB_CODENAME=`lsb_release -s -c`
            fi

            echo "-----> Configuring apt repo for salt #{salt_version}"
            echo "deb #{salt_apt_repo}/salt-#{salt_version} ${DISTRIB_CODENAME} main" | #{sudo('tee')} /etc/apt/sources.list.d/salt-#{salt_version}.list

            do_download #{salt_apt_repo_key} /tmp/repo.key
            #{sudo('apt-key')} add /tmp/repo.key

            #{sudo('apt-get')} update
            sleep 10
            echo "-----> Installing salt-minion (#{salt_version})"
            #{sudo('apt-get')} install -y python-support
            #{sudo('apt-get')} install -y salt-minion
            #{sudo('apt-get')} install -y salt-common
            #{sudo('apt-get')} install -y salt-minion
          elif [ -z "${SALT_VERSION}" -a "#{salt_install}" = "ppa" ]
          then
            #{sudo('apt-add-repository')} -y #{salt_ppa}
            #{sudo('apt-get')} update
            #{sudo('apt-get')} install -y salt-minion
          fi

          # check again, now that an install of some form should have happened
          SALT_VERSION=`salt-call --version | cut -d " " -f 2`

          if [ -z "${SALT_VERSION}" ]
          then
            echo "No salt-minion installed, install must have failed!!"
            echo "salt_install = #{salt_install}"
            echo "salt_url = #{salt_url}"
            echo "bootstrap_options = #{bootstrap_options}"
            echo "salt_version = #{salt_version}"
            echo "salt_apt_repo = #{salt_apt_repo}"
            echo "salt_apt_repo_key = #{salt_apt_repo_key}"
            echo "salt_ppa = #{salt_ppa}"
            exit 2
          elif [ "${SALT_VERSION}" = "#{salt_version}" -o "#{salt_version}" = "latest" ]
          then
            echo "You asked for #{salt_version} and you have ${SALT_VERSION} installed, sweet!"
          elif [ ! -z "${SALT_VERSION}" -a "#{salt_install}" = "bootstrap" ]
          then
            echo "You asked for bootstrap install and you have got ${SALT_VERSION}, hope thats ok!"
          else
            echo "You asked for #{salt_version} and you have got ${SALT_VERSION} installed, dunno how to fix that, sorry!"
            exit 2
          fi

          #{install_chef}

          '
        INSTALL
      end

      def install_chef
        return unless config[:require_chef]
        chef_url = config[:chef_bootstrap_url]
        omnibus_download_dir = config[:omnibus_cachier] ? '/tmp/vagrant-cache/omnibus_chef' : '/tmp'
        <<-INSTALL
          if [ ! -d "/opt/chef" ]
          then
            echo "-----> Installing Chef Omnibus (for busser/serverspec ruby support)"
            mkdir -p #{omnibus_download_dir}
            if [ ! -x #{omnibus_download_dir}/install.sh ]
            then
              do_download #{chef_url} #{omnibus_download_dir}/install.sh
            fi
            #{sudo('sh')} #{omnibus_download_dir}/install.sh -d #{omnibus_download_dir}
          fi
        INSTALL
      end

      def create_sandbox
        super
        prepare_data
        prepare_minion
        prepare_pillars
        prepare_grains

        if config[:state_collection] || config[:is_file_root]
          prepare_state_collection
        else
          prepare_formula config[:kitchen_root], config[:formula]

          unless config[:vendor_path].nil?
            if Pathname.new(config[:vendor_path]).exist?
              Dir[File.join(config[:vendor_path], '*')].each do |d|
                prepare_formula config[:vendor_path], File.basename(d)
              end
            else
              # :vendor_path was set, but not valid
              raise UserError, "kitchen-salt: Invalid vendor_path set: #{config[:vendor_path]}"
            end
          end
        end

        config[:dependencies].each do |formula|
          prepare_formula formula[:path], formula[:name]
        end
        prepare_state_top
      end

      def init_command
        debug("Initialising Driver #{name} by cleaning #{config[:root_path]}")
        "#{sudo('rm')} -rf #{config[:root_path]} ; mkdir -p #{config[:root_path]}"
      end

      def run_command
        debug("running driver #{name}")
        debug(diagnose)
        if config[:salt_run_highstate]
          cmd = sudo("salt-call --config-dir=#{File.join(config[:root_path], config[:salt_config])} --local state.highstate")
        end

        cmd << " --log-level=#{config[:log_level]}" if config[:log_level]

        # config[:salt_version] can be 'latest' or 'x.y.z', 'YYYY.M.x' etc
        # error return codes are a mess in salt:
        #  https://github.com/saltstack/salt/pull/11337
        # Unless we know we have a version that supports --retcode-passthrough
        # attempt to scan the output for signs of failure
        if config[:salt_version] > RETCODE_VERSION || config[:salt_version] == 'latest'
          # hope for the best and hope it works eventually
          cmd += ' --retcode-passthrough'
        else
          # scan the output for signs of failure, there is a risk of false negatives
          fail_grep = 'grep -e Result.*False -e Data.failed.to.compile -e No.matching.sls.found.for'
          # capture any non-zero exit codes from the salt-call | tee pipe
          cmd = 'set -o pipefail ; ' << cmd
          # Capture the salt-call output & exit code
          cmd << ' 2>&1 | tee /tmp/salt-call-output ; SC=$? ; echo salt-call exit code: $SC ;'
          # check the salt-call output for fail messages
          cmd << " (sed '/#{fail_grep}/d' /tmp/salt-call-output | #{fail_grep} ; EC=$? ; echo salt-call output grep exit code ${EC} ;"
          # use the non-zer exit code from salt-call, then invert the results of the grep for failures
          cmd << ' [ ${SC} -ne 0 ] && exit ${SC} ; [ ${EC} -eq 0 ] && exit 1 ; [ ${EC} -eq 1 ] && exit 0)'
        end

        cmd
      end
    end
  end
end
