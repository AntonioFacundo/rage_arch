# frozen_string_literal: true

module RageArch
  # Convention: a "dep" is any injectable external dependency (persistence, mailer, API).
  # Register it in RageArch::Container by symbol and resolve it in the use case with dep(:symbol).
  # No base class required; any object can be a dep.
  module Dep
  end
end
