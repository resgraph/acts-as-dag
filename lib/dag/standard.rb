module Dag
  module Standard
    def self.included(base)
      base.send(:include, NonPolyEdgeInstanceMethods)
    end

    # Encapsulates the necessary information about a graph node
    class EndPoint
      # Does an endpoint match another endpoint or model instance
      def matches?(other)
        id == other.id && scoped_record_id == other.scoped_record_id
      end

      # Factory Construction method that creates an endpoint from a model
      def self.from_resource(resource, scoped_record_id)
        new(resource.id, scoped_record_id)
      end

      # Factory Construction method that creates an endpoint from a model if necessary
      def self.from(obj, scoped_record_id)
        obj.is_a?(EndPoint) ? obj : from_resource(obj, scoped_record_id)
      end

      # Initializes an endpoint based on an Id
      def initialize(id, scoped_record_id)
        @id = id
        @scoped_record_id = scoped_record_id
      end

      attr_reader :id
      attr_reader :scoped_record_id
    end

    # Encapsulates information about the source of a link
    class Source < EndPoint
      # Factory Construction method creates a source instance from a link
      def self.from_edge(edge)
        scoped_record_id = edge.scoped_record_id_column_name ? edge.public_send(edge.scoped_record_id_column_name) : nil
        new(edge.ancestor_id, scoped_record_id)
      end
    end

    # Encapsulates information about the sink of a link
    class Sink < EndPoint
      # Factory Construction method creates a sink instance from a link
      def self.from_edge(edge)
        scoped_record_id = edge.scoped_record_id_column_name ? edge.public_send(edge.scoped_record_id_column_name) : nil
        new(edge.descendant_id, scoped_record_id)
      end
    end

    # Builds a hash that describes a link from a source and a sink
    def conditions_for(source, sink, scoped_record_id = nil)
      {
        ancestor_id_column_name => source.id,
        descendant_id_column_name => sink.id,
        scoped_record_id_column_name => scoped_record_id
      }.compact
    end

    # Instance methods included into the link model for a non-polymorphic DAG
    module NonPolyEdgeInstanceMethods
    end
  end
end
