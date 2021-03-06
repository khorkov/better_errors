require "spec_helper"

module BetterErrors
  describe ErrorPage do
    let!(:exception) { raise ZeroDivisionError, "you divided by zero you silly goose!" rescue $! }

    let(:error_page) { ErrorPage.new exception, { "PATH_INFO" => "/some/path" } }

    let(:response) { error_page.render }

    let(:empty_binding) {
      local_a = :value_for_local_a
      local_b = :value_for_local_b

      @inst_c = :value_for_inst_c
      @inst_d = :value_for_inst_d

      binding
    }

    it "includes the error message" do
      expect(response).to include("you divided by zero you silly goose!")
    end

    it "includes the request path" do
      expect(response).to include("/some/path")
    end

    it "includes the exception class" do
      expect(response).to include("ZeroDivisionError")
    end

    context "variable inspection" do
      let(:exception) { empty_binding.eval("raise") rescue $! }

      if BetterErrors.binding_of_caller_available?
        it "shows local variables" do
          html = error_page.do_variables("index" => 0)[:html]
          expect(html).to include("local_a")
          expect(html).to include(":value_for_local_a")
          expect(html).to include("local_b")
          expect(html).to include(":value_for_local_b")
        end
      else
        it "tells the user to add binding_of_caller to their gemfile to get fancy features" do
          html = error_page.do_variables("index" => 0)[:html]
          expect(html).to include(%{gem "binding_of_caller"})
        end
      end

      it "shows instance variables" do
        html = error_page.do_variables("index" => 0)[:html]
        expect(html).to include("inst_c")
        expect(html).to include(":value_for_inst_c")
        expect(html).to include("inst_d")
        expect(html).to include(":value_for_inst_d")
      end

      it "shows filter instance variables" do
        allow(BetterErrors).to receive(:ignored_instance_variables).and_return([ :@inst_d ])
        html = error_page.do_variables("index" => 0)[:html]
        expect(html).to include("inst_c")
        expect(html).to include(":value_for_inst_c")
        expect(html).not_to include('<td class="name">@inst_d</td>')
        expect(html).not_to include("<pre>:value_for_inst_d</pre>")
      end
    end

    it "doesn't die if the source file is not a real filename" do
      allow(exception).to receive(:backtrace).and_return([
        "<internal:prelude>:10:in `spawn_rack_application'"
      ])
      expect(response).to include("Source unavailable")
    end

    context 'with an exception with blank lines' do
      class SpacedError < StandardError
        def initialize(message = nil)
          message = "\n\n#{message}" if message
          super
        end
      end

      let!(:exception) { raise SpacedError, "Danger Warning!" rescue $! }

      it 'does not include leading blank lines in exception_message' do
        expect(exception.message).to match(/\A\n\n/)
        expect(error_page.exception_message).not_to match(/\A\n\n/)
      end
    end

    describe '#do_eval' do
      let(:exception) { empty_binding.eval("raise") rescue $! }
      subject(:do_eval) { error_page.do_eval("index" => 0, "source" => command) }
      let(:command) { 'EvalTester.stuff_was_done(:yep)' }
      before do
        stub_const('EvalTester', eval_tester)
      end
      let(:eval_tester) { double('EvalTester', stuff_was_done: 'response') }

      context 'with Pry disabled' do
        it "evaluates the code" do
          do_eval
          expect(eval_tester).to have_received(:stuff_was_done).with(:yep)
        end

        it 'returns a hash of the code and its result' do
          expect(do_eval).to include(
            highlighted_input: /stuff_was_done/,
            prefilled_input: '',
            prompt: '>>',
            result: "=> \"response\"\n",
          )
        end
      end

      context 'with Pry enabled' do
        before do
          BetterErrors.use_pry!
          # Cause the provider to be unselected, so that it will be re-detected.
          BetterErrors::REPL.provider = nil
        end
        after do
          BetterErrors::REPL::PROVIDERS.shift
          BetterErrors::REPL.provider = nil

          # Ensure the Pry REPL file has not been included. If this is not done,
          # the constant leaks into other examples.
          BetterErrors::REPL.send(:remove_const, :Pry)
        end

        it "evaluates the code" do
          BetterErrors::REPL.provider
          do_eval
          expect(eval_tester).to have_received(:stuff_was_done).with(:yep)
        end

        it 'returns a hash of the code and its result' do
          expect(do_eval).to include(
            highlighted_input: /stuff_was_done/,
            prefilled_input: '',
            prompt: '>>',
            result: "=> \"response\"\n",
          )
        end
      end
    end
  end
end
