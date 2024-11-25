module Dag
  module Polymorphic
    def self.included(base)
      base.send :include, PolyEdgeInstanceMethods
    end

    # Contains nested classes in the link model for polymorphic DAGs
    # Encapsulates the necessary information about a graph node
    class EndPoint
      # Does the endpoint match a model or another endpoint
      def matches?(other)
        if other.is_a?(EndPoint)
          id == other.id && type == other.type && scoped_record_id == other.scoped_record_id
        else
          id == other.id && type == other.class.to_s && scoped_record_id == other.scoped_record_id
        end
      end

      # Factory Construction method that creates an EndPoint instance from a model
      def self.from_resource(resource, scoped_record_id)
        new(resource.id, resource.class.to_s, scoped_record_id)
      end

      # Factory Construction method that creates an EndPoint instance from a model if necessary
      def self.from(obj, scoped_record_id)
        obj.is_a?(EndPoint) ? obj : from_resource(obj, scoped_record_id)
      end

      # Initializes the EndPoint instance with an id and type
      def initialize(id, type, scoped_record_id)
        @id = id
        @type = type
        @scoped_record_id = scoped_record_id
      end

      attr_reader :id
      attr_reader :type
      attr_reader :scoped_record_id
    end

    # Encapsulates information about the source of a link
    class Source < EndPoint
      # Factory Construction method that generates a source from a link
      def self.from_edge(edge)
        scoped_record_id = edge.scoped_record_id_column_name ? edge.public_send(edge.scoped_record_id_column_name) : nil
        new(edge.ancestor_id, edge.ancestor_type, scoped_record_id)
      end
    end

    # Encapsulates information about the sink (destination) of a link
    class Sink < EndPoint
      # Factory Construction method that generates a sink from a link
      def self.from_edge(edge)
        scoped_record_id = edge.scoped_record_id_column_name ? edge.public_send(edge.scoped_record_id_column_name) : nil
        new(edge.descendant_id, edge.descendant_type, scoped_record_id)
      end
    end

    # Contains class methods that extend the link model for polymorphic DAGs
    # Builds a hash that describes a link from a source and a sink
    def conditions_for(source, sink, scoped_record_id = nil)
      {
        ancestor_id_column_name => source.id,
        ancestor_type_column_name => source.type,
        descendant_id_column_name => sink.id,
        descendant_type_column_name => sink.type,
        scoped_record_id_column_name => scoped_record_id
      }.compact
    end

    # Instance methods included into link model for a polymorphic DAG
    module PolyEdgeInstanceMethods
      def ancestor_type
        self[ancestor_type_column_name]
      end

      def descendant_type
        self[descendant_type_column_name]
      end
    end
  end
end
