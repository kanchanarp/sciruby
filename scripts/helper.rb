begin
  require 'bundler/setup'
rescue Exception
end

$: << File.join(File.dirname(__FILE__), '..', 'lib')

require 'sciruby'
require 'date'
require 'rubygems'

module Enumerable
  def stable_sort_by
    sort_by.with_index {|e, i| [yield(e), i] }
  end
end

module Helper
  extend self

  def sort_hash(object)
    if Hash === object
      res = {}
      object.each {|k, v| res[k] = sort_hash(v) }
      Hash[res.sort_by {|a| a[0].to_s }]
    elsif Array === object
      array = []
      object.each_with_index {|v, i| array[i] = sort_hash(v) }
      array
    else
      object
    end
  end

  def check_gem(name, gem)
    gem[:name].must_equal name
    gem.must_be_instance_of Hash
    gem.each_key {|k| k.must_be_instance_of Symbol }
    gem[:category].must_be_instance_of String
    gem[:description].must_be_instance_of String
    gem[:exclude].must_be_instance_of String if gem[:exclude] != nil
    gem[:module].must_be_instance_of Array
    gem[:require].must_be_instance_of Array
    gem[:require].empty?.must_equal false

    if gem[:exclude] || gem[:owner] == 'stdlib' || %w(sciruby sciruby-full).include?(gem[:name])
      gem[:version].must_be_nil
    else
      gem[:version].must_be_instance_of String
    end
  end

  def fetch_spec(gem)
    #STDERR.puts "Fetching #{gem[:name]}..."
    dep = Gem::Dependency.new(gem[:name])
    spec = Gem::SpecFetcher.fetcher.spec_for_dependency(dep, false).flatten[-2]
    return spec if spec
    dep.prerelease = true
    Gem::SpecFetcher.fetcher.spec_for_dependency(dep, false).flatten[-2]
  end

  def label(tag, msg)
    %{<span class="label label-#{tag}">#{msg}</span>}
  end

  def gem_status(gem)
    status = []
    status << label(:default, "Excluded: #{gem[:exclude]}") if gem[:exclude]
    if gem[:spec]
      status << label(Time.now - gem[:spec].date > 4*365*24*3600 ? :danger : :warning, "Last update #{gem[:date]}") if Time.now - gem[:spec].date > 2*365*24*3600
      status << label(:danger, 'Outdated version constraint') if gem[:version] && !Gem::Dependency.new(gem[:name], *gem[:version]).matches_spec?(gem[:spec])
    else
      status << label(:danger, 'Gem not found') unless gem[:exclude] || gem[:owner] == 'stdlib'
    end
    status << %{<a class="label label-warning" href="https://versioneye.com/ruby/#{gem[:name]}">Outdated dependencies</a>} if versioneye(gem[:name])
    status << label(:success, 'OK') if status.empty?
    status.sort_by {|label| label =~ /label-\w+/; $& }.join(' ')
  end

  def table_gems
    require 'parallel'
    require 'net/http'
    require 'json'

    gems = SciRuby.gems.each_value.
           stable_sort_by {|gem| gem[:name] }.
           stable_sort_by {|gem| gem[:category] }.
           stable_sort_by {|gem| gem[:owner] == 'sciruby' ? 0 : (gem[:owner] ? 1 : 2) }.
           stable_sort_by {|gem| gem[:exclude] ? 1 : 0 }

    Parallel.map(gems, in_processes: 8) do |gem|
      gem = gem.dup

      if gem[:owner] == 'stdlib'
        gem[:homepage] = gem[:docs] = "http://ruby-doc.org/stdlib/libdoc/#{gem[:name]}/rdoc/"
        gem[:github] = "ruby/ruby/blob/trunk/lib/#{gem[:name]}.rb"
        gem[:module] = gem[:module].map {|mod| %{<a href="#{gem[:docs]}#{mod.gsub('::', '/')}.html">#{mod}</a>} }
      elsif spec = fetch_spec(gem)
        gem[:spec] = spec
        gem[:date] = spec.date.strftime('%Y-%m-%d')
        gem[:github] = github_name(gem)
        gem[:homepage] = spec.homepage
        gem[:docs] = "http://www.rubydoc.info/gems/#{gem[:name]}/#{spec.version}"
        gem[:module] = gem[:module].map {|mod| %{<a href="#{gem[:docs]}/#{mod.gsub('::', '/')}">#{mod}</a>} }
      end
      gem[:status] = gem_status(gem)

      gem
    end
  end

  def github_name(gem)
    return $1 if gem[:spec].homepage =~ %r{github.com/([^/]+/[^/]+)}
    JSON.parse(Net::HTTP.get(URI("https://rubygems.org/api/v1/gems/#{gem[:name]}.json"))).each do |k,v|
      return $1 if k =~ /_uri/ && v =~ %r{github.com/([^/]+/[^/]+)}
    end
    nil
  end

  def versioneye(name)
    Net::HTTP.get(URI("https://www.versioneye.com/ruby/#{name}/badge")) =~ /out of date/
  end

  def sciruby_gems(exclude)
    SciRuby.gems.each_value.sort_by {|gem| gem[:name] }.reject do |gem|
      gem[:owner] == 'stdlib' || %w(sciruby sciruby-full).include?(gem[:name])
    end.reject {|gem| gem[:exclude] && exclude }
  end
end
