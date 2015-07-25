require 'tempfile'

module GrassGis

  class Context
    ROOT_MODULES = %w(d g i r v s m p)
    REQUIRED_CONFIG = [:gisbase, :location]

    def initialize(config)
      # apply configuration defaults
      config[:gisdbase] ||= File.join(ENV['HOME'], 'grassdata')
      config[:mapset]  ||= ENV['USER']
      unless config[:version]
        version_file = File.join(config[:gisbase], 'etc', 'VERSIONNUMBER')
        if File.exists?(version_file)
          config[:version] = File.read(version_file).split.first
        end
      end
      config[:message_format] ||= 'plain'
      config[:true_color] = true unless config.key?(:true_color)
      config[:transparent] = true unless config.key?(:transparent)
      config[:png_auto_write] = true unless config.key?(:png_auto_write)
      config[:gnuplot] ||= 'gnuplot -persist'
      config[:gui] ||= 'wxpython'

      config[:errors] ||= :raise
      config[:echo] = :commands unless config.key?(:echo)

      @config = config

      locals = config[:locals] || {}
      locals.each do |var_name, value|
        define_singleton_method(var_name){ value }
      end
    end

    # Commands executed in the session are kept in the +history+ array
    #
    #    GrassGis.session config do
    #       g.region res: 10
    #       g.region res: 20
    #       g.region res: 30
    #       puts history[-3] # => "g.region res=10"
    #       puts history[-2] # => "g.region res=20"
    #       puts history[-1] # => "g.region res=30"
    #       puts history[-2].output
    #    end
    #
    attr_reader :history

    # Last command executed in the session (history[-1])
    def last
      history.last
    end

    # Array of commands that resulted in error in the session
    def errors
      history.select { |cmd| GrassGis.error?(cmd) }
    end

    # Did last command exit with error status
    def error?
      GrassGis.error? last
    end

    def error_info
      GrassGis.error_info last
    end

    # Output of the last command executed
    def output
      last.output
    end

    # Standar error output of last command executed
    def error_output
      last.error_output
    end

    def configuration
      @config
    end

    def allocate
      @gisrc = Tempfile.new('gisrc')
      @gisrc.puts "LOCATION_NAME: #{@config[:location]}"
      @gisrc.puts "GISDBASE: #{@config[:gisdbase]}"
      @gisrc.puts "MAPSET: #{@config[:mapset]}"
      @gisrc.puts "GUI: #{@config[:gui]}"
      @gisrc.close

      @original_env = {}

      replace_var 'GISRC', @gisrc.path
      replace_var 'GISBASE', @config[:gisbase]
      replace_var 'GRASS_VERSION', @config[:version]
      replace_var 'GRASS_MESSAGE_FORMAT', @config[:message_format].to_s
      replace_var 'GRASS_TRUECOLOR', bool_var(@config[:true_color])
      replace_var 'GRASS_TRANSPARENT', bool_var(@config[:transparent])
      replace_var 'GRASS_PNG_AUTO_WRITE', bool_var(@config[:png_auto_write])
      replace_var 'GRASS_GNUPLOT', @config[:gnuplot]

      paths = ['bin', 'scripts']
      if OS.windows?
        # paths << 'lib'
        paths.unshift 'lib'
      else
        insert_path 'LD_LIBRARY_PATH', File.join(@config[:gisbase], 'lib')
        ENV['GRASS_LD_LIBRARY_PATH'] = ENV['LD_LIBRARY_PATH']
      end
      paths = paths.map { |path| File.join(@config[:gisbase], path) }
      if OS.windows?
        osgeo4w_dir = ENV['OSGEO4W_ROOT'] || "C:\\OSGeo4W"
        if File.directory?(osgeo4w_dir)
          paths << File.join(osgeo4w_dir, 'bin')
        end
      end
      insert_path 'PATH', *paths
      insert_path 'MANPATH', File.join(@config[:gisbase], 'man')
      @history = []
    end

    def dispose
      @gisrc.unlink if @gisrc
      @gisrc = nil
      @original_env.each do |var, value|
        ENV[var] = value
      end
      @original_env = {}
    end

    # setup access to the root modules in the context
    ROOT_MODULES.each do |root_module|
      define_method root_module.to_sym do
        var_name = "@#{root_module}"
        m = instance_variable_get(var_name)
        m ||= Module.new(root_module, context: self)
        instance_variable_set var_name, m
        m
      end
    end

    # Evaluate a block of code in the context of a GRASS session
    #
    # Useful to pass a GRASS context around and use it to execute
    # GRASS commands, e.g.:
    #
    #     def helper(grass, ...)
    #        # can invoke GRASS commands using grass:
    #        grass.g.region res: 10
    #        # Or use a session block to abbreviate typing:
    #        grass.session do
    #          g.region res: 10
    #          ...
    #        end
    #     end
    #
    #     GrassGis.session ... do
    #       helper seld, ...
    #       ...
    #     end
    #
    def session(&blk)
      if blk.arity == 1
        blk.call self
      else
        instance_eval &blk
      end
    end

    def dry?
      @config[:dry]
    end

    def execute(cmd)
      @history << cmd
      if @config[:echo]
        puts cmd.to_s(with_input: false)
      end
      log_file = @config[:log] || @config[:history]
      if log_file
        log_timestamp log_file
        log log_file, cmd.to_s(with_input: true)
      end
      unless dry?
        cmd.run error_output: :separate
      end
      if cmd.output
        puts cmd.output if @config[:echo] == :output
      end
      handle_errors cmd
      cmd
    end

  private

    def log_timestamp(file)
      log file, Time.now
    end

    def log(file, message)
      if file && message
        File.open(file, 'a') do |log_file|
          log_file.puts message
        end
      end
    end

    def handle_errors(cmd)
      GrassGis.error cmd, @config[:errors]
      if @config[:echo] == :output || @config[:log] || @config[:errors] == :console
        error_info = GrassGis.error_info(cmd)
        if error_info
          if @config[:errors] == :console || @config[:echo] == :output
            STDERR.puts error_info
          end
          log @config[:log], error_info
        end
      end
    end

    def bool_var(value)
      value ? 'TRUE' : 'FALSE'
    end

    def insert_path(var, *paths)
      @original_env[var] = ENV[var]
      if File::ALT_SEPARATOR
        paths = paths.map { |path| path.gsub(File::SEPARATOR, File::ALT_SEPARATOR) }
      end
      paths << ENV[var] if ENV[var]
      ENV[var] = paths.join(File::PATH_SEPARATOR)
    end

    def replace_var(var, value)
      @original_env[var] = ENV[var]
      ENV[var] = value
    end

  end

  # Evaluate a block in a GRASS session environment
  # The configuration must include at leaast:
  #
  # * :gibase The base GRASS instalation directory
  # * :location The location to work with
  #
  # Optional parameters:
  #
  # * :gisdbase The base GRASS data directory
  # * :mapset The default mapset
  # * :version The GRASS version
  #
  # Example:
  #
  #     configuration = {
  #       gisbase: '/usr/local/Cellar/grass-70/7.0.0/grass-7.0.0',
  #       location: 'world'
  #     }
  #
  #     GrassGis.session configuration do
  #       r.resamp.stats '-n', input: "map1@mapset1", output: "map2"
  #       cmd = g.list 'vect'
  #       puts cmd.output
  #     end
  #
  # Note that block is evaluated in a spacial context, so
  # that the lexical scope's self and instance variables
  # are not directly available inside it.
  # Local variables in the scope can be used to access self-related
  # information. Also, local values can be injected in the block
  # with the +:locals+ option:
  #
  #     this = self # make self available a local variable
  #     locals = { context: self } # inject locals
  #     GrassGis.session configuration.merge(locals:) do
  #          r.resamp.stats '-n', input: this.input, output: context.output
  #     end
  #
  # Other pararameters:
  #
  # :errors to define the behaviour when a GRASS command fails:
  # * :raise is the default and raises on errors
  # * :console shows standar error output of commands
  # * :quiet error output is retained but not shown; no exceptions are
  #   raise except when the command cannot be executed (e.g. when
  #   the command name is ill-formed)
  #
  # If :errors is anything other than :raise, it is up to the user
  # to check each command for errors. With the :console option
  # the standar error output of commands is sent to the console
  # and is not accessible through the command's error_output method.
  #
  # :log is used to define a loggin file where executed commands
  # and its output is written.
  #
  # :history is used to define a loggin file where only
  # executed commands are written.
  #
  # :echo controls what is echoed to the standard output
  # and can be one of the following options:
  # * :commands show all executed commands (the default)
  # * :output show the output of commands too
  # * false don't echo anything
  #
  # Testing/debugging options:
  #
  # * :dry prevents actual execution of any command
  # * errors: :silent omits raising exceptions (as :quiet) even when
  #   a command cannot be executed (usually because of an invalid command name)
  #
  def self.session(config, &blk)
    context = Context.new(config)
    context.allocate
    context.session &blk
  ensure
    context.dispose if context
  end

  class Error < StandardError
  end

  def self.error?(command)
    command && (!!command.error || (command.status_value && command.status_value != 0))
  end

  def self.error_info(command)
    if command
      if command.error
        info = "Error (#{command.error.class}):\n"
        info << command.error.to_s
      elsif (command.status_value && command.status_value != 0)
        info = "Exit code #{command.status_value}\n"
        info << command.error_output if command.error_output
      end
    end
  end

  def self.error(command, error_mode = :raise)
    if command
      if command.error # :silent mode for testing/debugging?
        # Errors that prevent command execution
        # (usually ENOENT because the command does not exist)
        # are always raised
        raise command.error unless error_mode == :silent
      elsif error_mode == :raise
        if (command.status_value && command.status_value != 0)
          raise Error.new, error_info(command)
        end
      end
    end
  end

end
