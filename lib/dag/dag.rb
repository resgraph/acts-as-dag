module Dag
  # Sets up a model to act as dag links for models specified under the :for option
  def acts_as_dag_links(options = {})
    options = {
      ancestor_id_column: "ancestor_id",
      ancestor_type_column: "ancestor_type",
      descendant_id_column: "descendant_id",
      descendant_type_column: "descendant_type",
      direct_column: "direct",
      count_column: "count",
      polymorphic: false,
      node_class_name: nil,
      scoped_record_id_column: nil
    }.merge(options)

    if options[:polymorphic].blank? && options[:node_class_name].blank?
      raise ActiveRecord::ActiveRecordError,
            "ERROR: Non-polymorphic graphs need to specify :node_class_name with the receiving class like belong_to"
    end

    class_attribute :acts_as_dag_options, instance_writer: false
    self.acts_as_dag_options = options

    extend Columns
    include Columns

    # access to _changed? and _was for (edge,count) if not default
    unless direct_column_name == "direct"
      module_eval <<-"END_EVAL", __FILE__, __LINE__ + 1
        def direct_changed?
          self.#{direct_column_name}_changed?
        end

        def direct_was
          self.#{direct_column_name}_was
        end
      END_EVAL
    end

    unless count_column_name == "count"
      module_eval <<-"END_EVAL", __FILE__, __LINE__ + 1
        def count_changed?
          self.#{count_column_name}_changed?
        end

        def count_was
          self.#{count_column_name}_was
        end
      END_EVAL
    end

    internal_columns = [ancestor_id_column_name, descendant_id_column_name]

    direct_column_name.intern
    count_column_name.intern

    # links to ancestor and descendant
    if acts_as_dag_polymorphic?
      extend PolyColumns
      include PolyColumns

      internal_columns << ancestor_type_column_name
      internal_columns << descendant_type_column_name

      belongs_to :ancestor, polymorphic: true
      belongs_to :descendant, polymorphic: true

      validates ancestor_type_column_name.to_sym, presence: true
      validates descendant_type_column_name.to_sym, presence: true
      uniqueness_scope = [ancestor_type_column_name, descendant_type_column_name, descendant_id_column_name]
      uniqueness_scope << scoped_record_id_column_name.to_sym if scoped_record_id_column_name.present?
      validates ancestor_id_column_name.to_sym, uniqueness: { scope: uniqueness_scope }

      scope :with_ancestor, lambda { |ancestor, scoped_record_id = nil|
        scope = where(ancestor_id_column_name => ancestor.id, ancestor_type_column_name => ancestor.class.to_s)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }

      scope :with_descendant, lambda { |descendant, scoped_record_id = nil|
        scope = where(descendant_id_column_name => descendant.id, descendant_type_column_name => descendant.class.to_s)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }

      scope :with_ancestor_point, lambda { |point, scoped_record_id = nil|
        scope = where(ancestor_id_column_name => point.id, ancestor_type_column_name => point.type)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }

      scope :with_descendant_point, lambda { |point, scoped_record_id = nil|
        scope = where(descendant_id_column_name => point.id, descendant_type_column_name => point.type)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }

      extend Polymorphic
      include Polymorphic
    else
      belongs_to :ancestor, foreign_key: ancestor_id_column_name, class_name: acts_as_dag_options[:node_class_name]
      belongs_to :descendant, foreign_key: descendant_id_column_name, class_name: acts_as_dag_options[:node_class_name]

      uniqueness_scope = [descendant_id_column_name]
      uniqueness_scope << scoped_record_id_column_name.to_sym if scoped_record_id_column_name.present?
      validates ancestor_id_column_name.to_sym, uniqueness: { scope: uniqueness_scope }

      scope :with_ancestor, lambda { |ancestor, scoped_record_id = nil|
        scope = where(ancestor_id_column_name => ancestor.id)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }

      scope :with_descendant, lambda { |descendant, scoped_record_id = nil|
        scope = where(descendant_id_column_name => descendant.id)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }

      scope :with_ancestor_point, lambda { |point, scoped_record_id = nil|
        scope = where(ancestor_id_column_name => point.id)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }
      scope :with_descendant_point, lambda { |point, scoped_record_id = nil|
        scope = where(descendant_id_column_name => point.id)
        scope = scope.where(scoped_record_id_column_name => scoped_record_id) if scoped_record_id_column_name.present?
        scope
      }

      extend Standard
      include Standard
    end

    scope :direct, -> { where(direct: true) }

    scope :indirect, -> { where(direct: false) }

    scope :ancestor_nodes, -> { joins(:ancestor) }

    scope :descendant_nodes, -> { joins(:descendant) }

    validates :ancestor, presence: true
    validates :descendant, presence: true

    extend Edges
    include Edges

    before_destroy :destroyable!, :perpetuate
    before_save :perpetuate
    before_validation :field_check, :fill_defaults, on: :update
    before_validation :fill_defaults, on: :create

    include ActiveModel::Validations
    validates_with CreateCorrectnessValidator, on: :create
    validates_with UpdateCorrectnessValidator, on: :update

    # internal fields
    code = ["def field_check \n"]
    internal_columns.each do |column|
      code << "if #{column}_changed? \n raise ActiveRecord::ActiveRecordError, \"Column: #{column} cannot be changed for an existing record it is immutable\"\n end \n"
    end
    code << "end"
    module_eval(code.join)

    [count_column_name].each do |column|
      module_eval <<-"END_EVAL", __FILE__, __LINE__ + 1
        def #{column}=(x)
          raise ActiveRecord::ActiveRecordError,
                "ERROR: Unauthorized assignment to #{column}: it's an internal field handled by acts_as_dag code."
        end
      END_EVAL
    end
  end

  def has_dag_links(options = {})
    options = {
      class_name: nil,
      prefix: "",
      ancestor_class_names: [],
      descendant_class_names: [],
      scoped_record_id_column: nil
    }.merge(options)

    # check that class_name is filled
    if options[:link_class_name].nil?
      raise ActiveRecord::ActiveRecordError, "has_dag_links must be provided with :link_class_name option"
    end

    # add trailing '_' to prefix
    options[:prefix] = "#{options[:prefix]}_" unless options[:prefix] == ""

    prefix = options[:prefix]
    dag_link_class_name = options[:link_class_name]
    dag_link_class = options[:link_class_name].constantize
    if options[:scoped_record_id_column].present?
      scoped_record_condition = ",#{options[:scoped_record_id_column]}: record.#{options[:scoped_record_id_column]}"
      lambda_scoped_record_condition = "lambda { |record| where(#{options[:scoped_record_id_column]}:
                                       record.#{options[:scoped_record_id_column]}) },".squish

      class_eval <<-EOL0, __FILE__, __LINE__ + 1
        attr_accessor :#{options[:scoped_record_id_column]}
      EOL0
    else
      class_eval <<-EOL0, __FILE__, __LINE__ + 1
        attr_accessor :scoped_record_id
      EOL0
    end

    if dag_link_class.acts_as_dag_polymorphic?
      class_eval <<-EOL1, __FILE__, __LINE__ + 1
        has_many :#{prefix}links_as_ancestor,#{lambda_scoped_record_condition} as: :ancestor, class_name: "#{dag_link_class_name}"
        has_many :#{prefix}links_as_descendant,#{lambda_scoped_record_condition} as: :descendant, class_name: "#{dag_link_class_name}"
        has_many :#{prefix}links_as_parent, lambda { |record| where(#{dag_link_class.direct_column_name}: true#{scoped_record_condition}) }, as: :ancestor, class_name: "#{dag_link_class_name}"
        has_many :#{prefix}links_as_child, lambda { |record| where(#{dag_link_class.direct_column_name}: true#{scoped_record_condition}) }, as: :descendant, class_name: "#{dag_link_class_name}"
      EOL1

      ancestor_table_names = []
      parent_table_names = []
      options[:ancestor_class_names].each do |class_name|
        table_name = class_name.tableize
        class_eval <<-EOL2, __FILE__, __LINE__ + 1
          has_many :#{prefix}links_as_descendant_for_#{table_name}, lambda { |record| where(#{dag_link_class.ancestor_type_column_name}: "#{class_name}"#{scoped_record_condition}) }, as: :descendant, class_name: "#{dag_link_class_name}"
          has_many :#{prefix}ancestor_#{table_name}, through: :#{prefix}links_as_descendant_for_#{table_name}, source: :ancestor, source_type: "#{class_name}"
          has_many :#{prefix}links_as_child_for_#{table_name}, lambda { |record| where(#{dag_link_class.ancestor_type_column_name}: "#{class_name}", "#{dag_link_class.direct_column_name}": true#{scoped_record_condition}) }, as: :descendant, class_name: "#{dag_link_class_name}"
          has_many :#{prefix}parent_#{table_name}, through: :#{prefix}links_as_child_for_#{table_name}, source: :ancestor, source_type: "#{class_name}"

          def #{prefix}root_for_#{table_name}?
            self.links_as_descendant_for_#{table_name}.empty?
          end
        EOL2
        ancestor_table_names << ("#{prefix}ancestor_#{table_name}")
        parent_table_names << ("#{prefix}parent_#{table_name}")
        next if options[:descendant_class_names].include?(class_name)

        # this apparently is only one way is we can create some aliases making things easier
        class_eval "has_many :#{prefix}#{table_name}, through: :#{prefix}links_as_descendant_for_#{table_name}, source: :ancestor, source_type: \"#{class_name}\"",
                   __FILE__, __LINE__ - 1
      end

      if options[:ancestor_class_names].empty?
        class_eval <<-EOL26, __FILE__, __LINE__ + 1
          def #{prefix}ancestors
            #{prefix}links_as_descendant.map(&:ancestor)
          end

          def #{prefix}parents
            #{prefix}links_as_child.map(&:ancestor)
          end
        EOL26
      else
        class_eval <<-EOL25, __FILE__, __LINE__ + 1
          def #{prefix}ancestors
            #{ancestor_table_names.join(' + ')}
          end

          def #{prefix}parents
            #{parent_table_names.join(' + ')}
          end
        EOL25
      end

      descendant_table_names = []
      child_table_names = []
      options[:descendant_class_names].each do |class_name|
        table_name = class_name.tableize
        class_eval <<-EOL3, __FILE__, __LINE__ + 1
          has_many :#{prefix}links_as_ancestor_for_#{table_name}, lambda { |record| where(#{dag_link_class.descendant_type_column_name}: "#{class_name}"#{scoped_record_condition}) }, as: :ancestor, class_name: "#{dag_link_class_name}"
          has_many :#{prefix}descendant_#{table_name}, through: :#{prefix}links_as_ancestor_for_#{table_name}, source: :descendant, source_type: "#{class_name}"

          has_many :#{prefix}links_as_parent_for_#{table_name}, lambda { |record| where(#{dag_link_class.descendant_type_column_name}: "#{class_name}", #{dag_link_class.direct_column_name}: true#{scoped_record_condition}) }, as: :ancestor, class_name: "#{dag_link_class_name}"
          has_many :#{prefix}child_#{table_name}, through: :#{prefix}links_as_parent_for_#{table_name}, source: :descendant, source_type: "#{class_name}"

          def #{prefix}leaf_for_#{table_name}?
            self.links_as_ancestor_for_#{table_name}.empty?
          end
        EOL3
        descendant_table_names << ("#{prefix}descendant_#{table_name}")
        child_table_names << ("#{prefix}child_#{table_name}")
        unless options[:ancestor_class_names].include?(class_name)
          class_eval "has_many :#{prefix}#{table_name}, through: :#{prefix}links_as_ancestor_for_#{table_name}, source: :descendant, source_type: \"#{class_name}\"",
                     __FILE__, __LINE__ - 1
        end
      end

      if options[:descendant_class_names].empty?
        class_eval <<-EOL36, __FILE__, __LINE__ + 1
          def #{prefix}descendants
            #{prefix}links_as_ancestor.map(&:descendant)
          end

          def #{prefix}children
            #{prefix}links_as_parent.map(&:descendant)
          end
        EOL36
      else
        class_eval <<-EOL35, __FILE__, __LINE__ + 1
          def #{prefix}descendants
            #{descendant_table_names.join(' + ')}
          end

          def #{prefix}children
            #{child_table_names.join(' + ')}
          end
        EOL35
      end
    else
      class_eval <<-EOL4, __FILE__, __LINE__ + 1
        has_many :#{prefix}links_as_ancestor,#{lambda_scoped_record_condition} foreign_key: "#{dag_link_class.ancestor_id_column_name}", class_name: "#{dag_link_class_name}"
        has_many :#{prefix}links_as_descendant,#{lambda_scoped_record_condition} foreign_key: "#{dag_link_class.descendant_id_column_name}", class_name: "#{dag_link_class_name}"

        has_many :#{prefix}ancestors, through: :#{prefix}links_as_descendant, source: :ancestor
        has_many :#{prefix}descendants, through: :#{prefix}links_as_ancestor, source: :descendant

        has_many :#{prefix}links_as_parent, lambda { |record| where(#{dag_link_class.direct_column_name}: true#{scoped_record_condition}) }, foreign_key: "#{dag_link_class.ancestor_id_column_name}", class_name: "#{dag_link_class_name}", inverse_of: :ancestor
        has_many :#{prefix}links_as_child, lambda { |record| where(#{dag_link_class.direct_column_name}: true#{scoped_record_condition}) }, foreign_key: "#{dag_link_class.descendant_id_column_name}", class_name: "#{dag_link_class_name}", inverse_of: :descendant

        has_many :#{prefix}parents, through: :#{prefix}links_as_child, source: :ancestor
        has_many :#{prefix}children, through: :#{prefix}links_as_parent, source: :descendant
      EOL4
    end
    class_eval <<-EOL5, __FILE__, __LINE__ + 1
      def #{prefix}self_and_ancestors
        [self] + #{prefix}ancestors
      end

      def #{prefix}self_and_descendants
        [self] + #{prefix}descendants
      end

      def #{prefix}leaf?
        self.#{prefix}links_as_ancestor.empty?
      end

      def #{prefix}root?
        self.#{prefix}links_as_descendant.empty?
      end
    EOL5
  end
end
