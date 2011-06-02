
set :project,           'biomart-server'
set :repository,        'svn+ssh://svn.internal.sanger.ac.uk/repos/svn/htgt/projects/biomart/biomart-server/trunk'
set :umask,             '002'
set :service_user,      'team87'
set :service_group,     'team87'
set :custom_env_setup,  '/software/bin/perl -I/software/team87/brave_new_world/lib/perl5 -I/software/team87/brave_new_world/lib/perl5/x86_64-linux-thread-multi /software/team87/brave_new_world/bin/htgt-env.pl --live' 


# usage: rake ENVIRONMENT vlad:TASK

##
## Our environments
##

task :ikmc_mart_ikmc_vm do
  # This is a production instance only
  set :biomart_env,       'ikmc_mart_ikmc_vm'
  set :custom_env_setup,  nil
  set :service_user,      't87svc'
  set :service_group,     't87svc'
  set :domain,            't87adm@ikmc.vm.bytemark.co.uk'
  set :deploy_to,         '/opt/t87/software/ikmc-mart/server'
  set :rebuilddir,        "#{deploy_to.gsub('/server','/rebuild')}/current"
  set :log_dir,           '/opt/t87/logs/ikmc-mart'
end

task :ikmc_mart_htgt_test do
  set :biomart_env,       'ikmc_mart_htgt_test'
  set :domain,            'htgt.internal.sanger.ac.uk'
  set :deploy_to,         '/nfs/team87/services/biomart/ikmc-mart/test/server'
  set :rebuilddir,        "#{deploy_to.gsub('/server','/rebuild')}/current"
  set :log_dir,           '/software/team87/brave_new_world/logs/ikmc-mart/test'
end

task :ikmc_mart_htgt_production do
  set :biomart_env,       'ikmc_mart_htgt_production'
  set :domain,            'htgt.internal.sanger.ac.uk'
  set :deploy_to,         '/nfs/team87/services/biomart/ikmc-mart/production/server'
  set :rebuilddir,        "#{deploy_to.gsub('/server','/rebuild')}/current"
  set :log_dir,           '/software/team87/brave_new_world/logs/ikmc-mart/production'
end

task :htgt_mart_htgt_test do
  set :biomart_env,       'htgt_mart_htgt_test'
  set :domain,            'htgt.internal.sanger.ac.uk'
  set :deploy_to,         '/nfs/team87/services/biomart/htgt-mart/test/server'
  set :rebuilddir,        "#{deploy_to.gsub('/server','/rebuild')}/current"
  set :log_dir,           '/software/team87/brave_new_world/logs/htgt-mart/test'
end

task :htgt_mart_htgt_production do
  set :biomart_env,       'htgt_mart_htgt_production'
  set :domain,            'htgt.internal.sanger.ac.uk'
  set :deploy_to,         '/nfs/team87/services/biomart/htgt-mart/production/server'
  set :rebuilddir,        "#{deploy_to.gsub('/server','/rebuild')}/current"
  set :log_dir,           '/software/team87/brave_new_world/logs/htgt-mart/production'
end

task :unitrap_mart_htgt_test do
  set :biomart_env,       'unitrap_mart_htgt_test'
  set :domain,            'htgt.internal.sanger.ac.uk'
  set :deploy_to,         '/nfs/team87/services/biomart/unitrap-mart/test/server'
  set :rebuilddir,        "#{deploy_to.gsub('/server','/rebuild')}/current"
  set :log_dir,           '/software/team87/brave_new_world/logs/unitrap-mart/test'
end

task :unitrap_mart_helmholtz_production do
  set :biomart_env,       'unitrap_mart_helmholtz_production'
  set :ssh_flags,         '-p 54321'
  set :rsync_flags,       ["-e 'ssh -p 54321'", '-azP', '--delete']
  set :custom_env_setup,  nil
  set :service_user,      nil
  set :service_group,     nil
  set :domain,            'biomart@idcc-devel.helmholtz-muenchen.de'
  set :deploy_to,         '/opt/biomart/server'
  set :rebuilddir,        "#{deploy_to.gsub('/server','/rebuild')}/current"
  set :log_dir,           '/opt/biomart/logs'
end

##
## Tasks
##

namespace :vlad do
  Rake.clear_tasks('vlad:setup','vlad:setup_app')
  Rake.clear_tasks('vlad:migrate','vlad:update','vlad:rollback')
  Rake.clear_tasks('vlad:start','vlad:start_app','vlad:start_web')
  Rake.clear_tasks('vlad:stop','vlad:stop_web')
  
  ##
  ## Deployment
  ##
  
  desc "Deploy the latest version of the #{project} codebase"
  task :deploy => [
    'vlad:export_code',
    'vlad:stop',
    'vlad:update_permissions_and_symlinks',
    'vlad:reconfigure',
    'vlad:start',
    'vlad:cleanup'
  ]
  
  task :export_code do
    begin
      Dir.mktmpdir do |dir|
        Dir.mkdir("#{dir}/export")
        `#{svn_cmd} export --force #{repository} #{dir}/export`
        `#{rsync_cmd} #{rsync_flags.join(' ')} #{dir}/export/. #{domain}:#{release_path}`
      end
    rescue => e
      raise e
    end
  end
  
  remote_task :update_permissions_and_symlinks, :roles => :app do
    symlink = false
    begin
      commands = [
        "umask #{umask}",
        "chmod -R g+w #{latest_release}",
        "chmod 02775 #{latest_release}",
        "rm -rf #{latest_release}/logs",
        "ln -nfs #{log_dir} #{latest_release}/logs",
      ]
      
      commands << "cp #{current_path}/conf/httpd.conf #{latest_release}/conf/httpd.conf" if File.exists?("#{current_path}/conf/httpd.conf")
      commands << "chgrp -R #{service_group} #{latest_release}/conf" if service_group
      
      run commands.join(" && ")
      
      symlink = true
      commands = [
        "umask #{umask}",
        "rm -f #{current_path}",
        "ln -s #{latest_release} #{current_path}",
        "echo #{now} $USER #{revision} #{File.basename(release_path)} >> #{deploy_to}/revisions.log"
      ]
      
      run commands.join(' && ')
    rescue => e
      run "rm -f #{current_path} && ln -s #{previous_release} #{current_path}" if symlink
      run "rm -rf #{release_path}"
      raise e
    end
  end
  
  remote_task :rollback do
    if releases.length < 2 then
      abort "could not rollback the code because there is no prior release"
    else
      run "rm -f #{current_path}; ln -s #{previous_release} #{current_path} && rm -rf #{current_release}"
    end

    Rake::Task['vlad:restart'].invoke
  end
  
  ##
  ## Stop/Start/Restart
  ##
  
  desc "Stop a BioMart server"
  remote_task :stop, :roles => :app do
    cmd = custom_env_setup ? "#{custom_env_setup}" : "bash -l -c"
    cmd << " \"ruby server.rb --environment #{biomart_env} --rebuilddir #{rebuilddir} --stop"
    cmd << " --service_user #{service_user}" if service_user
    cmd << "\""
    
    commands = [ "cd #{current_path}", cmd ]
    run commands.join(' && ')
  end
  
  desc "Reconfigure a BioMart server"
  remote_task :reconfigure, :roles => :app do
    cmd = custom_env_setup ? "#{custom_env_setup}" : "bash -l -c"
    cmd << " \"ruby server.rb --environment #{biomart_env} --rebuilddir #{rebuilddir} --reconfigure"
    cmd << " --service_user #{service_user}" if service_user
    cmd << "\""
    
    commands = [ "cd #{current_path}", cmd ]
    run commands.join(' && ')
    
    if domain == 'htgt.internal.sanger.ac.uk'
      begin
        more_commands = [
          "chgrp -fR #{service_group} #{current_path}/conf/Cached",
          "chgrp -fR #{service_group} #{current_path}/conf/Cached_backup",
          "chgrp -fR #{service_group} #{current_path}/conf/cachedRegistries",
          "chgrp -fR #{service_group} #{current_path}/conf/templates",
          "chgrp -fR #{service_group} #{current_path}/cgi-bin",
          "chgrp -fR #{service_group} #{current_path}/htdocs/martview"
        ]
        run more_commands.join(' && ')
      rescue => e
      end
      
      fix_perms = "find #{current_path}/ -user #{`whoami`.chomp}" + ' \! \( -perm -u+rw -a -perm -g+rw \) -exec chmod -v ug=rwX,o=rX {} \;'
      run fix_perms
    end
  end
  
  desc "Start a BioMart server"
  remote_task :start, :roles => :app do
    cmd = custom_env_setup ? "#{custom_env_setup}" : "bash -l -c"
    cmd << " \"ruby server.rb --environment #{biomart_env} --rebuilddir #{rebuilddir} --start"
    cmd << " --service_user #{service_user}" if service_user
    cmd << "\""
    
    commands = [ "cd #{current_path}", cmd ]
    run commands.join(' && ')
  end
  
  desc "Restart a BioMart server (stop/reconfigure/start)"
  task :restart => [
    'vlad:stop',
    'vlad:reconfigure',
    'vlad:start'
  ]
  
  ##
  ## Setup
  ##
  
  remote_task :setup, :roles => :app do
    dirs = [deploy_to, releases_path]
    dirs = dirs.join(' ')
    
    commands = [
      "umask #{umask}",
      "mkdir -p #{dirs}"
    ]
    
    if service_user
      commands << "sudo -u #{service_user} mkdir -p #{log_dir}"
      commands << "sudo -u #{service_user} touch #{log_dir}/error_log"
      commands << "sudo -u #{service_user} touch #{log_dir}/access_log"
      commands << "sudo -u #{service_user} touch #{log_dir}/log4perl_log"
      commands << "sudo -u #{service_user} chmod g+w -R #{log_dir}"
    else
      commands << "mkdir -p #{log_dir}"
      commands << "touch #{log_dir}/error_log"
      commands << "touch #{log_dir}/access_log"
      commands << "touch #{log_dir}/log4perl_log"
      commands << "chmod g+w -R #{log_dir}"
    end
    
    run commands.join(' && ')
  end
end
