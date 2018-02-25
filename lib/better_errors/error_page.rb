require "cgi"
require "json"
require "securerandom"

# creates the errors, passes them along to the error page.

module BetterErrors
  # @private
  class ErrorPage
    #finds the path to the template to add error information to
    def self.template_path(template_name)
      File.expand_path("../templates/#{template_name}.erb", __FILE__)
    end
    #finds the path to the template to add error information to
    def self.template(template_name)
      Erubi::Engine.new(File.read(template_path(template_name)), escape: true)
    end

    attr_reader :exception, :env, :repls

    def initialize(exception, env)
      @exception = RaisedException.new(exception)
      @env = env
      @start_time = Time.now.to_f
      @repls = []
    end

    def id
      @id ||= SecureRandom.hex(8)
    end
    # renders a template
    def render(template_name = "main")
      binding.eval(self.class.template(template_name).src)
    end
    # I believe this shows the variables used within a page
    def do_variables(opts)
      index = opts["index"].to_i
      @frame = backtrace_frames[index]
      @var_start_time = Time.now.to_f
      { html: render("variable_info") }
    end

    def do_eval(opts)
      index = opts["index"].to_i
      code = opts["source"]

      unless (binding = backtrace_frames[index].frame_binding)
        return { error: "REPL unavailable in this stack frame" }
      end

      @repls[index] ||= REPL.provider.new(binding, exception)

      eval_and_respond(index, code)
    end

    def backtrace_frames
      exception.backtrace
    end

    def exception_type
      exception.type
    end

    def exception_message
      exception.message.lstrip
    end

    def application_frames
      backtrace_frames.select(&:application?)
    end

    def first_frame
      application_frames.first || backtrace_frames.first
    end

    private
    def editor_url(frame)
      BetterErrors.editor[frame.filename, frame.line]
    end

    def rack_session
      env['rack.session']
    end

    def rails_params
      env['action_dispatch.request.parameters']
    end

    def uri_prefix
      env["SCRIPT_NAME"] || ""
    end

    def request_path
      env["PATH_INFO"]
    end

    def html_formatted_code_block(frame)
      CodeFormatter::HTML.new(frame.filename, frame.line).output
    end

    def text_formatted_code_block(frame)
      CodeFormatter::Text.new(frame.filename, frame.line).output
    end

    def text_heading(char, str)
      str + "\n" + char*str.size
    end
    # inspects the value of an object
    def inspect_value(obj)
      inspect_raw_value(obj)
    rescue NoMethodError
      "<span class='unsupported'>(object doesn't support inspect)</span>"
    rescue Exception => e
      "<span class='unsupported'>(exception #{CGI.escapeHTML(e.class.to_s)} was raised in inspect)</span>"
    end
    #determines the value to return to the error page for a given object being inspected.
    # depending on the size of the variable error message, if the variable should be passed or if we should
    # suggest that the variable be shortened
    def inspect_raw_value(obj)
      value = CGI.escapeHTML(obj.inspect)

      if value_small_enough_to_inspect?(value)
        value
      else
        "<span class='unsupported'>(object too large. "\
          "Modify #{CGI.escapeHTML(obj.class.to_s)}#inspect "\
          "or increase BetterErrors.maximum_variable_inspect_size)</span>"
      end
    end
    #determines if a value is small enough to inspect. Currently using the length of the value 
    #as the indicator if it should be shortened or not.
    def value_small_enough_to_inspect?(value)
      return true if BetterErrors.maximum_variable_inspect_size.nil?
      value.length <= BetterErrors.maximum_variable_inspect_size
    end

    def eval_and_respond(index, code)
      result, prompt, prefilled_input = @repls[index].send_input(code)

      {
        highlighted_input: CodeRay.scan(code, :ruby).div(wrap: nil),
        prefilled_input:   prefilled_input,
        prompt:            prompt,
        result:            result
      }
    end
  end
end
