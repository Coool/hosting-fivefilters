# Puppet file intended to install server componenets for FiveFilters.org web services
# This file is intended for base images of:
# Ubuntu 15.10
# Note: this does not install PHP-CLD or the PECL HTTP extension, as we couldn't get these
# to run with PHP7. We'll try again at a later time. If these are
# important for you, please use one of our earlier Puppet scripts (15.04).

Exec { path => "/bin:/usr/bin:/usr/local/bin" }

stage { 'first': before => Stage['main'] }
stage { 'last': require => Stage['main'] }

class {
	'init': stage => first;
	'final': stage => last;
}

class init {
	package { "python-software-properties":
		ensure => latest,
		before => Exec["php7-repo"]
	}
	package { "fail2ban":
		ensure => latest
	}
	exec { "php7-repo":
		command => "sudo LC_ALL=en_US.UTF-8 add-apt-repository ppa:ondrej/php",
		#notify => Exec["apt-update"]
	}
	exec { "apt-update": 
		command => "sudo apt-get update"
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
	exec { "apt-update": 
		command => "sudo apt-get update"
	}
	package { "php7.0": ensure => latest }
	#package { "php-apc": ensure => latest }
	package { "libapache2-mod-php7.0": ensure => latest }
	package { "php7.0-cli": ensure => latest }
	package { "php7.0-tidy": ensure => latest }
	package { "php7.0-curl": ensure => latest }
	package { "libcurl4-gnutls-dev": ensure => latest }
	package { "libpcre3-dev": ensure => latest }
	package { "make": ensure=>latest }
	package { "php-pear": ensure => latest }
	package { "php7.0-dev": ensure => latest }
	package { "php7.0-intl": ensure => latest }
	package { "php7.0-gd": ensure => latest }
	package { "php-imagick": ensure => latest }
	package { "php7.0-json": ensure => latest }
	#package { "php-http": ensure => latest }
	#package { "php5-raphf": ensure => latest }
	#package { "php5-propro": ensure => latest }
	file { "/etc/php/mods-available/fivefilters-php.ini":
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
		require => Package["php7.0"],
		before => Exec["enable-fivefilters-php"],
	}
	exec { "enable-fivefilters-php":
		command => "sudo phpenmod fivefilters-php",
	}	
}

class php_pecl_http {
  # Important: this file needs to be in place before we install the HTTP extension
	file { "/etc/php/mods-available/http.ini":
		ensure => present,
		#owner => root, group => root, mode => 444,
		content => "; priority=25
extension=raphf.so
extension=propro.so
extension=http.so",
		before => [Exec["install-http-pecl"], Exec["enable-http"]],
		require => Class["php"]
	}

	exec { "enable-http":
		command => "sudo phpenmod http",
		require => Class["php"],
	}

	exec { "install-http-pecl":
		command => "sudo pecl install pecl_http",
		# the above is now version 2.0 - supported in Full-Text RSS 3.5
		#command => "pecl install http://pecl.php.net/get/pecl_http-1.7.6.tgz",
		#creates => "/tmp/needed/directory",
		require => Exec["enable-http"]
	}
}

class php_pecl_apcu {
	exec { "install-apcu-pecl":
		command => "sudo pecl install channel://pecl.php.net/APCu-5.1.3",
		#creates => "/tmp/needed/directory",
		require => Class["php"]
	}

	file { "/etc/php/mods-available/apcu.ini":
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

class php_cld {
	# see https://github.com/lstrojny/php-cld
	package { "git": ensure => latest }
	
	package { "build-essential": ensure => latest }
	
	file { "/tmp/cld":
		ensure => absent,
		before => Exec["download-cld"],
		recurse => true,
		force => true
	}
	
	exec { "download-cld":
		command => "git clone git://github.com/lstrojny/php-cld.git /tmp/cld",
		require => [Package["git"], Class["php"]],
		before => Exec["build-cld"]
	}
	
	exec { "checkout-cld-version":
		# recent version does not work, so we switch to an older one
		command => "git reset --hard fd5aa5721b01bfe547ff6674fa0daa9c3b791ca3",
		cwd => "/tmp/cld",
		require => Exec["download-cld"],
		before => Exec["build-cld"]
	}
	
	exec { "build-cld":
		command => "./build.sh",
		#new cld:command => "sh compile_libs.sh",
		cwd => "/tmp/cld/vendor/libcld",
		require => Package["build-essential"],
		provider => "shell"
	}
	
	exec { "install-cld-extension":
		command => "phpize && ./configure --with-libcld-dir=/tmp/cld/vendor/libcld && make && sudo make install",
		cwd => "/tmp/cld",
		provider => "shell",
		require => Exec["build-cld"]
	}

	file { "/etc/php/mods-available/cld.ini":
		ensure => present,
		#owner => root, group => root, mode => 444,
		content => "extension=cld.so",
		require => Exec["install-cld-extension"],
		before => Exec["enable-cld"],
	}

	exec { "enable-cld":
		command => "sudo phpenmod cld",
		notify => Exec["restart-apache"],
	}
}

class final {
}

include init
include apache
include php
include php_pecl_apcu
#include php_cld
#include php_pecl_http
include final