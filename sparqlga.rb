require_relative 'ga'
require_relative 'chromosome'
require_relative 'sparqllib'
require 'fileutils'

class SPARQLGA < GeneticAlgorithm
  @@chr_size = -1
  def initialize(size)
    @@chr_size = size
  end

  def generate(chromosome)
    value = (0..(@@chr_size-1)).to_a.shuffle
  
    chromosome.new(value)
  end

  def get_chr_size
    return @@chr_size
  end
  def select(population)
    # sort by fitness_value
    newary = population.sort! { |a,b| b.get_fitness_value <=> a.get_fitness_value }
    # sum of fitness_value for selection
    sum = newary.inject(0) { |sum, ch| sum + ch.get_fitness_value }
    # select parent 1
    p1rand = rand(0..sum)
    f = 0
    p1 = newary[0]
    newary.each{|ch|
      f += ch.get_fitness_value
      if f >= p1rand
        p1 = ch
        break
      end
    }
    # select parent 2
    # parent 2 is not the same as parent 1
    sum = sum - p1.get_fitness_value
    p2rand = rand(0..sum)
    f = 0
    p2 = newary[1]
    newary.each{|ch|
      if ch == p1
        next
      end
      f += ch.get_fitness_value
      if f >= p2rand
        p2 = ch
        break
      end
    }
    return [p1, p2]
  end
  def run(chromosome, p_cross, p_mutation, iterations = 100,population_size = 100)
    # initial population
    population = population_size.times.map { generate(chromosome) }
    current_generation = population
    next_generation    = []
    #
    alltime_best = population[0]

    iterations.times {|cnt|
      #
      puts "Generation #{cnt}"
      # Exec fitness function
      current_generation.each { |ch| ch.fitness }
      # max
      best_fit = current_generation.max_by { |ch| ch.get_fitness_value }.dup

      if best_fit.get_fitness_value > alltime_best.get_fitness_value
        alltime_best = best_fit.dup
      end

      puts "Best fit: #{best_fit.value} => #{best_fit.get_fitness_value}, elapsed time: #{best_fit.get_elapsed_time}"
      (population.size / 2).times {
        selection = select(current_generation)
        # crossover
        selection = crossover(selection, chromosome)
        # mutation
        selection[0].mutate(p_mutation)
        selection[1].mutate(p_mutation)
        # 
        next_generation << selection[0] << selection[1]
      }
      # NOTE: last generation is not evaluated
      current_generation = next_generation
      next_generation    = []
    }

    # return best solution
    puts "All times Best fit: Chr #{alltime_best.value} => #{alltime_best.get_fitness_value}, elapsed time: #{alltime_best.get_elapsed_time}"

    "#{alltime_best.value} => #{alltime_best.get_fitness_value}, elapsed time: #{alltime_best.get_elapsed_time}"
  end
  # Croossover method  is OX
  def crossover(selection, chromosome)
    i1 = rand(0..@@chr_size-1)
    i2 = rand(i1..@@chr_size-1)
    if i1 == i2
        return selection
    end
    a1 = selection[0].value
    a2 = selection[1].value
    cr1 = Array.new(@@chr_size,-1)
    cr2 = Array.new(@@chr_size,-1)
    i1.upto(i2) { |i|
      cr1[i] = a1[i]
      cr2[i] = a2[i]
    }
    s1 = a2-cr1
    s2 = a1-cr2
    0.upto(s1.size-1) { |i|
      cr1[(i2+1+i)%@@chr_size] = s1[i]
      cr2[(i2+1+i)%@@chr_size] = s2[i]
    }

    [chromosome.new(cr1), chromosome.new(cr2)]
  end
end
class SparqlChromosome < Chromosome
  @@output_sparql_directory = ""
  @@output_time_directory = ""

  @@fitness_value_cache = {}
  @@elapsed_time_cache = {}

  @@endpoint = "https://integbio.jp/togosite/sparql"
  @@rq = <<'SPARQL'.chop
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX taxon: <http://identifiers.org/taxonomy/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX faldo: <http://biohackathon.org/resource/faldo#>
PREFIX dc: <http://purl.org/dc/elements/1.1/>

SELECT DISTINCT ?parent ?child ?child_label
FROM <http://rdf.integbio.jp/dataset/togosite/ensembl>
WHERE {
  ?enst obo:SO_transcribed_from ?ensg .
  ?ensg a ?parent ;
        obo:RO_0002162 taxon:9606 ;
        faldo:location ?ensg_location ;
        dc:identifier ?child ;
        rdfs:label ?child_label .
  FILTER(CONTAINS(STR(?parent), "terms/ensembl/"))
  BIND(STRBEFORE(STRAFTER(STR(?ensg_location), "GRCh38/"), ":") AS ?chromosome)
  VALUES ?chromosome {
      "1" "2" "3" "4" "5" "6" "7" "8" "9" "10"
      "11" "12" "13" "14" "15" "16" "17" "18" "19" "20" "21" "22"
      "X" "Y" "MT"
  }
}
SPARQL
  # executed sparql
  @executed_sparql = ""
  def initialize(value)
    super(value)
    # create result directory
    t = Time.now
    timestr = t.strftime("%Y%m%dT%H%M%S")
    @@output_sparql_directgory =  FileUtils.mkdir_p("result/#{timestr}/sparql")[0]
    @@output_time_directory = FileUtils.mkdir_p("result/#{timestr}/time/")[0]
  end    
  def fitness
    # check result is in cached
    if @@fitness_value_cache.has_key?(@value)
      @fitness_value = @@fitness_value_cache[@value]
      @elapsed_time = @@elapsed_time_cache[@value]
      return @fitness_value
    end
    
    sga = SparqlLib.new(@@endpoint)
    sga.set_original_query(@@rq)
    puts "Chr: #{@value}"
    @executed_sparql = sga.create_new_querystring(@value)
    @resulttime = sga.exec_sparql_query(@executed_sparql)
    if @resulttime==-1
      @fitness_value = 0
    else
      @fitness_value = 1/@resulttime
    end
    @@fitness_value_cache[@value] = @fitness_value
    @@elapsed_time_cache[@value] = @resulttime
    save_result()
    return @fitness_value
  end

  def mutate(probability_of_mutation)
    value.each_with_index do |x, i|
      if rand < probability_of_mutation
        pos = rand(0..(SIZE-1))
        @value[i] = @value[pos]
        @value[pos] = x
      end
    end    
  end

  def save_result
    # file prefix made by chromosome value
    prefix = @value.join("_")
    # save result
    
    File.open("#{@@output_sparql_directgory}/#{prefix}.rq", 'w') { |f|
      f.puts @executed_sparql
    }
    # save elapsed time
    File.open("#{@@output_time_directory}/#{prefix}.time.txt", 'w') { |f|
      f.puts @resulttime
    }
  end

  def get_elapsed_time
    @@elapsed_time_cache[@value]
  end
end


# ga = SPARQLGA.new(10)
# # show ga @@char_size
# puts ga.get_chr_size
# #chr= ga.generate(SparqlChromosome)
# # puts chr.get_chr
# puts ga.run(SparqlChromosome, 0.2, 0.01, 100)
endpoint = "https://integbio.jp/togosite/sparql"
rq = <<'SPARQL'.chop
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX taxon: <http://identifiers.org/taxonomy/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX faldo: <http://biohackathon.org/resource/faldo#>
PREFIX dc: <http://purl.org/dc/elements/1.1/>

SELECT DISTINCT ?parent ?child ?child_label
FROM <http://rdf.integbio.jp/dataset/togosite/ensembl>
WHERE {
  ?enst obo:SO_transcribed_from ?ensg .
  ?ensg a ?parent ;
        obo:RO_0002162 taxon:9606 ;
        faldo:location ?ensg_location ;
        dc:identifier ?child ;
        rdfs:label ?child_label .
  FILTER(CONTAINS(STR(?parent), "terms/ensembl/"))
  BIND(STRBEFORE(STRAFTER(STR(?ensg_location), "GRCh38/"), ":") AS ?chromosome)
  VALUES ?chromosome {
      "1" "2" "3" "4" "5" "6" "7" "8" "9" "10"
      "11" "12" "13" "14" "15" "16" "17" "18" "19" "20" "21" "22"
      "X" "Y" "MT"
  }
}
SPARQL

# 
ga = SPARQLGA.new(6)
puts ga.run(SparqlChromosome, 0.2, 0.01, iteration=3, population_size=10)