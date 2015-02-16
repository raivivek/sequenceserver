require 'set'
require 'sequenceserver/config.rb'
require 'sequenceserver/database.rb'
require 'sequenceserver/sequence.rb'

module SequenceServer
  # Doctor detects inconsistencies likely to cause problems with your database.
  class Doctor
    class << self
      extend Forwardable

      def_delegators SequenceServer, :config

      def init
        @invalids    = check_parseq_ids
        @nt_seqids   = all_sequence_ids('nucleotide')
        @prot_seqids = all_sequence_ids('protein')
      end

      def diagnose
        puts '*** Running SequenceServer Doctor.'
        puts '1/6 Building an index of databases. This may take a while..'
        init

        puts "\n2/6 Inspecting databases for proper -parseq_ids formatting.."

        @invalids.each do |f|
          puts "*** Doctor has found improperly formatted database: #{f.title}"
        end

        puts "\n3/6 Inspecting databases for numeric sequence ids.."
        check_numeric_ids

        puts "\n4/6 Inspecting databases for non-unique sequence ids.."
        check_unique_ids

        puts "\n5/6 Inspecting databases for problematic sequence ids.."
        check_id_format

        puts "\n6/6 Inspecting files for consistent file permission.."
        check_file_permissions
      end

      private

      def show_message(msg, database)
        puts <<MSG
*** Doctor has found #{msg} in #{database.type} database: #{database.title}
MSG
      end

      def inspect_unique_ids(seqids)
        seqids.map do |sq|
          sq[:db] unless sq[:seqids].length == sq[:seqids].to_set.length
        end.compact!
      end

      def inspect_seqids(seqids, &block)
        seqids.map do |sq|
          sq[:db] unless sq[:seqids].select(&block).empty?
        end.compact!
      end

      def inspect_file_access
        File.readable?(config.data[:database_dir]) &&
          File.writable?(config.config_file) &&
          File.writable?(config.data[:database_dir])
      end

      def all_sequence_ids(type)
        Database.map do |db|
          next if db.type != type ||
                  @invalids.include?(db)

          out = `blastdbcmd -entry all -db #{db.name} -outfmt "%a" 2> /dev/null`
          {
            :db     => db,
            :seqids => out.to_s.split
          }
        end.compact!
      end

      def check_parseq_ids
        Database.select do |f|
          !(File.exist?([f.name, '.nsd'].join) ||
            File.exist?([f.name, '.psd'].join))
        end
      end

      def check_unique_ids
        inspect_unique_ids(@nt_seqids).each do |f|
          show_message('non-unique sequence ids', f)
        end

        inspect_unique_ids(@prot_seqids).each do |f|
          show_message('non-unique sequence ids', f)
        end
      end

      def check_numeric_ids
        selector = proc { |id| !id.to_i.zero? }

        inspect_seqids(@nt_seqids, &selector).each do |f|
          show_message('numeric sequence ids', f)
        end

        inspect_seqids(@prot_seqids, &selector).each do |f|
          show_message('numeric sequence ids', f)
        end
      end

      # Warn users about sequence identifiers of format abc|def because then
      # BLAST+ appends a gnl (for general) infront of the database
      # identifiers. There are only two identifiers that we need to avoid
      # when searching for this format.[1]
      # bbs|number, gi|number
      def check_id_format
        avoid_regex = /^>(?!gi|bbs)\w+\|\w*$/
        selector = proc { |id| id.match(avoid_regex) }

        inspect_seqids(@nt_seqids, &selector).each do |f|
          show_message('problematic sequence ids', f)
        end

        inspect_seqids(@prot_seqids, &selector).each do |f|
          show_message('problematic sequence ids', f)
        end
      end

      def check_file_permissions
        return if inspect_file_access
        puts <<MSG
*** Doctor has found inconsistent file permissions.'
    Please ensure that your config file and BLAST databasese are readable and
    writable by your account.
MSG
      end
    end
  end
end

# [1]: http://etutorials.org/Misc/blast/Part+IV+Industrial-Strength+BLAST/Chapter+11.+BLAST+Databases/11.1+FASTA+Files/
