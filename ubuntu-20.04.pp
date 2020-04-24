# Puppet file intended to install server componenets for FiveFilters.org web services
# This file is intended for base images of:
# Ubuntu 20.04
# On a *new* Ubuntu 20.04 server instance (Hetzner Cloud/Linode/Digital Ocean, etc.):
# > apt-get update
# > apt-get install puppet
# > puppet apply ubuntu-20.04.pp

Exec { path => "/bin:/usr/bin:/usr/local/bin" }

stage { 'first': before => Stage['main'] }
stage { 'last': require => Stage['main'] }

class {
	'init': stage => first;
	'final': stage => last;
}

class init {
	exec { "apt-update": 
		command => "apt-get update"
	}
	package { "fail2ban":
		ensure => latest
	}
	package { "unattended-upgrades":
		ensure => latest
	}
	file { "/etc/apt/apt.conf.d/20auto-upgrades":
		ensure => present,
		content => 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";',
		require => Package["unattended-upgrades"]
	}
	#exec { "configure-unattended-upgrades":
	#	require => Package["unattended-upgrades"],
	#	command => "sudo dpkg-reconfigure unattended-upgrades",
	#}
}

# make sure apt-update run before package
Exec["apt-update"] -> Package <| |>

class apache {
	exec { "enable-mod_rewrite":
		require => Package["apache2"],
		before => Service["apache2"],
		#command => "/usr/sbin/a2enmod rewrite",
		command => "sudo a2enmod rewrite",
	}

	file { "/etc/apache2/mods-available/mpm_prefork.conf":
		ensure => present,
		content => "<IfModule mpm_prefork_module>
        StartServers                     5
        MinSpareServers           5
        MaxSpareServers          10
        MaxRequestWorkers         80
        MaxConnectionsPerChild   0
</IfModule>",
		require => Package["apache2"],
		notify => Exec["restart-apache"]
	}
	
	exec { "enable-prefork":
		require => Package["apache2"],
		command => "sudo a2dismod mpm_event && sudo a2enmod mpm_prefork",
	}	

	file { "/etc/apache2/sites-available/fivefilters.conf":
		ensure => present,
		content => "<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html

        ErrorLog /var/log/apache2/error.log
        CustomLog /dev/null combined
        #CustomLog /var/log/apache2/access.log combined
        
				KeepAliveTimeout 2
				MaxKeepAliveRequests 10
</VirtualHost>",
		require => Package["apache2"],
		before => Exec["enable-fivefilters-apache2"],
		notify => Exec["restart-apache"]
	}

	exec { "enable-fivefilters-apache2":
		require => [Package["apache2"], Service["apache2"]],
		command => "sudo a2dissite 000-default && sudo a2ensite fivefilters"
	}

	exec { "disable-mod_status":
		require => Package["apache2"],
		before => Service["apache2"],
		command => "sudo a2dismod status",
	}

	package { "apache2":
		ensure => latest
	}

	service { "apache2":
		ensure => running,
		require => Package["apache2"]
	}

	exec { "restart-apache":
		command => "sudo service apache2 restart",
		require => Package["apache2"],
		refreshonly => true
	}
	#TODO: Set AllowOverride All in default config to enable .htaccess
}

class php {
	package { "php7.4": ensure => latest }
    #package { "php-apcu": ensure => latest }
    #package { "php-apcu-bc": ensure => latest }
	#package { "php-apc": ensure => latest }
	package { "libapache2-mod-php": ensure => latest }
	package { "php7.4-cli": ensure => latest }
	package { "php7.4-tidy": ensure => latest }
	package { "php7.4-curl": ensure => latest }
	#package { "libcurl4-gnutls-dev": ensure => latest }
	package { "libcurl4-openssl-dev": ensure => latest }
	package { "libpcre3-dev": ensure => latest }
	package { "make": ensure=>latest }
	package { "php-pear": ensure => latest }
	package { "php7.4-dev": ensure => latest }
	package { "php7.4-intl": ensure => latest }
	package { "php7.4-gd": ensure => latest }
	package { "php7.4-mbstring": ensure => latest }
	package { "php7.4-imagick": ensure => latest }
	package { "php7.4-json": ensure => latest }
	package { "php7.4-http": ensure => latest }
	#package { "php-raphf": ensure => latest }
	#package { "php-propro": ensure => latest }
	package { "php-zip": ensure => latest }


	file { "/etc/php/7.4/mods-available/fivefilters-php.ini":
		ensure => present,
		content => "engine = On
		expose_php = Off
		max_execution_time = 120
		memory_limit = 128M
		error_reporting = E_ALL & ~E_DEPRECATED
		display_errors = Off
		display_startup_errors = Off
		html_errors = Off
		default_socket_timeout = 120
		file_uploads = Off
		date.timezoe = 'UTC'",
		require => Package["php7.4"],
		before => Exec["enable-fivefilters-php"],
	}
	exec { "enable-fivefilters-php":
		command => "sudo phpenmod fivefilters-php",
	}	
}

class php_pecl_apcu {
	exec { "install-apcu-pecl":
		command => "sudo pecl install channel://pecl.php.net/APCu-5.1.18",
		#creates => "/tmp/needed/directory",
		require => Class["php"]
	}

	file { "/etc/php/7.4/mods-available/apcu.ini":
		ensure => present,
		#owner => root, group => root, mode => 444,
		content => "extension=apcu.so",
		require => Exec["install-apcu-pecl"],
		before => Exec["enable-apcu"]
	}
	exec { "enable-apcu":
		command => "sudo phpenmod apcu",
		notify => Exec["restart-apache"],
	}
}


class php_pecl_apc_bc {
	exec { "install-apc-bc-pecl":
		command => "sudo pecl install channel://pecl.php.net/apcu_bc-1.0.5",
		#creates => "/tmp/needed/directory",
		require => Class["php_pecl_apcu"]
	}

	file { "/etc/php/7.4/mods-available/z_apc_bc.ini":
		ensure => present,
		#owner => root, group => root, mode => 444,
		content => "extension=apc.so",
		require => Exec["install-apc-bc-pecl"],
		before => Exec["enable-apc-bc"]
	}
	exec { "enable-apc-bc":
		command => "sudo phpenmod z_apc_bc",
		notify => Exec["restart-apache"],
	}
}


class final {
	exec { "lower-swappiness":
		command => "echo 'vm.swappiness = 10' >> /etc/sysctl.conf && sudo sysctl -p",
		provider => "shell"
	}
	exec { "enable-php":
		command => "sudo a2enmod php7.4 && sudo service apache2 restart",
		provider => "shell"
	}
}

include init
include apache
include php
include php_pecl_apcu
include php_pecl_apc_bc
include final