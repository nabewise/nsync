# because the outdated git-ruby version is not interface compatible with grit,
# we have to prevent it from being used
module Jeweler::Specification
  def set_jeweler_defaults(base_dir, git_base_dir = nil)
    base_dir = File.expand_path(base_dir)
    git_base_dir = if git_base_dir
                     File.expand_path(git_base_dir)
                   else
                     base_dir
                   end
    can_git = git_base_dir && base_dir.include?(git_base_dir) && File.directory?(File.join(git_base_dir, '.git'))

    Dir.chdir(git_base_dir) do
      all_files = `git ls-files`.split("\n").reject{|file| file =~ /^\./ }

      if blank?(files)
        base_dir_with_trailing_separator = File.join(base_dir, "")

        self.files = all_files.reject{|file| file =~ /^(doc|pkg|test|spec|examples)/ }.compact.map do |file|
          File.expand_path(file).sub(base_dir_with_trailing_separator, "")
        end
      end

      if blank?(test_files)
        self.test_files = all_files.select{|file| file =~ /^(test|spec|examples)/ }.compact.map do |file|
          File.expand_path(file).sub(base_dir_with_trailing_separator, "")
        end
      end

      if blank?(executables)
        self.executables = all_files.select{|file| file =~ /^bin/}.map do |file|
          File.basename(file)
        end
      end

      if blank?(extensions)
        self.extensions = FileList['ext/**/{extconf,mkrf_conf}.rb']
      end

      self.has_rdoc = true

      if blank?(extra_rdoc_files)
        self.extra_rdoc_files = FileList['README*', 'ChangeLog*', 'LICENSE*', 'TODO']
      end

      if File.exist?('Gemfile')
        require 'bundler'
        bundler = Bundler.load
        bundler.dependencies_for(:default, :runtime).each do |dependency|
          self.add_dependency dependency.name, *dependency.requirement.as_list
        end
        bundler.dependencies_for(:development).each do |dependency|
          self.add_development_dependency dependency.name, *dependency.requirement.as_list
        end
      end
      
    end
  end
end
