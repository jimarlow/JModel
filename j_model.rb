require 'rexml/document'
include REXML

#local_variables.each { |v| eval("@#{v}=eval(v)") }

# VP UML requires extra features in JAssociation
$vp_uml = false

# Extend the REXML:Element xml element class
class Element
  def add_attrs ( attributes )
    attributes.each { | k, v | add_attribute( k, v ) unless v == nil }
  end
end

# A UML-like element class
class JModelElement
  attr_reader :name, :documentation, :id
  def initialize( name = "", documentation = nil )
    @name = name
    @model_elements = {}
    @documentation = nil
    @id = self.object_id.to_s()
    add_documentation( documentation ) if documentation
  end
  
  def add_documentation ( doc )
    @documentation = JDocumentation.new doc
    @documentation.bind self
    return self
  end
  
  def << ( e )
    @model_elements[ e.name ] = e
    return e
  end
  
  def add_model_elements_to!( element )
    @model_elements.values.each {|v| element.add_element v.get_element }
    element.add_element( @documentation.get_element ) if @documentation
    return element
  end
  
  def get_all_model_elements( all_model_elements = {} )
    @model_elements.each do | k, v | 
      all_model_elements[ k ] = v
      v.get_all_model_elements( all_model_elements ) 
    end
    return all_model_elements
  end

  # Resolve missing methods into accessors for model_elements
  def method_missing( m, *args, &block )
    me = @model_elements[ m.to_s ]
    if me then
      return me 
    else
      puts "Error: #{self}, #{self.name}: There's no method called #{m} here -- please try again."
      return nil
    end
  end
  
  def new_element( name, tag_attributes )
    element = Element.new name
    element.add_attrs tag_attributes 
    return element
  end
end

class JDocumentation < JModelElement
  attr_accessor :documentation
  def initialize( documentation )
    super()
    @documentation = documentation
    @annotated_element = nil
  end

  # When Documentation is added to a JModelElement, it should be bound to
  # that element in order to provide the annotatedElement attribute
  # for the XMI
  def bind( annotated_element )
    @annotated_element = annotated_element
    return self
  end

  def get_element()
    element = new_element "ownedComment", { "xmi:type" => "uml:Comment", "xmi:id" => @id }
    element.add_element "annotatedElement", { "xmi:idref" => @annotated_element.id }
    element.add_element( "body" ).add_text @documentation
    return element
  end
end

class JPackage < JModelElement
  def initialize( name, documentation = nil ) 
    super( name, documentation ) 
  end
  
  # Adders
  def add_package( name, documentation = nil ) 
    self << this = JPackage.new( name, documentation ) 
    yield( this ) if block_given?
    return self
  end 
   
  def add_class( name, documentation = nil ) 
    self << this = JClass.new( name, documentation ) 
    yield( this ) if block_given?
    return self
  end 
  
  def add_enumeration( name, documentation = nil ) 
    self << this = JEnumeration.new( name, documentation )
    yield( this ) if block_given?    
    return self
  end
  
  # Get the XML elements
  def get_element()
    element = new_element "packagedElement", { "xmi:type" => "uml:Package", "xmi:id" => @id, "name" => @name, "visibility" => "public" }
    add_model_elements_to! element
    return element
  end
end

class JModel < JPackage
  attr_reader :name, :model_elements
  def initialize( name, documentation = nil ) 
    super name, documentation 
  end
  
  # Looks for any attributes that have types given as strings, such as "Test", 
  # and resolves these names to an object if possible
  def resolve_attributes()
    types = get_all_model_elements.select{ |k,v| (v.class == JClass) || (v.class == JEnumeration) }
    attrs = get_all_model_elements.select{ |k,v| (v.class == JAttribute) && (v.type.class == String) }
    attrs.each { |k,v| v.type = types[ v.type ] if types[ v.type ] } 
  end

  def get_element()
    root = new_element "xmi:XMI", { "xmi:version" => "2.1", "xmlns:uml" => "http://schema.omg.org/spec/UML/2.2", "xmlns:xmi" => "http://schema.omg.org/spec/XMI/2.1" }
    model = root.add_element "uml:Model", { "name" => @name }
    @model_elements.values.each {|v| model.add_element v.get_element }
    return root
  end
  
  def add_association( class_1, role_1, multiplicity_1, multiplicity_2, role_2, class_2 )
    self << JAssociation.new( class_1, role_1, multiplicity_1, multiplicity_2, role_2, class_2 )
  end
end

class JClass < JModelElement
  attr_reader :parents
  def initialize( name, documentation = nil )
    super name, documentation
    @operations = {}
    @parents = {}
  end

  # Add a parent
  def add_parent( e )
    @parents[ e ] = nil if e.class == String        # It is a class name
    @parents[ e.name ] = e if e.class == JClass     # It is a class
    return self
  end
  
  def add_attribute( name, type = nil, multiplicity = nil, documentation = nil )
    self << this = JAttribute.new( name, type, multiplicity, documentation )
    yield( this ) if block_given?
    return self
  end
  
  def add_operation( name, visibility = "public", documentation = nil )
    self << this = JOperation.new( name, visibility, documentation )
    yield( this ) if block_given?
    return self
  end

  def get_element( p = {} )
    element = new_element "ownedMember", { "isAbstract" => "false", "isLeaf" => "false", "name" => @name, "visibility" => "public", "xmi:id" => @id, "xmi:type" => "uml:Class" }
    @model_elements.values.each {| a | element.add_element a.get_element }
    @parents.values.each { | p | element.add_element JGeneralization.new( p ).get_element }
    add_model_elements_to! element
    return element
  end
  
end

class JGeneralization < JModelElement
  attr_accessor :parent
  def initialize( parent )
    super()
    @parent = parent
  end

  def get_element()
    return ( element = new_element "generalization", { "general" => @parent.id, "xmi:id" => @id, "xmi:type" => "uml:Generalization" } )
  end

end

class JAttribute < JModelElement
  attr_accessor :name, :type, :multiplicity
  def initialize( name, type = nil, multiplicity = nil, documentation = nil )
    super name, documentation
    @type = type
    @multiplicity = multiplicity
  end

  def << ( e )
    # Can't add anything to an attribute apart from documentation
    return e
  end

  def get_element()
    # Sometimes, when creating a model, the attribute type is given as a String value.
    # This should be resolved to a real value.
    if  @type || (@type.class == String ) then
      element = new_element "ownedAttribute", { "xmi:type" => "uml:Property", "xmi:id" => @id, "name" => @name }      
    else
      element = new_element "ownedAttribute", { "xmi:type" => "uml:Property", "xmi:id" => @id, "name" => @name, "type" => @type.get_element }
    end
    upper_value = element.add_element( "upperValue", { "xmi:type" => "uml:LiteralUnlimitedNatural", "xmi:id" => @multiplicity.object_id.to_s(), "visibility" => "public", "value" => @multiplicity } ) if @multiplicity
    add_model_elements_to! element
    return element
  end
end

class JOperation < JModelElement
  def initialize( name, visibility = "public", documentation = nil )
    super name, documentation
    @visibility = visibility
  end
  
  def add_parameter( name, type = nil, documentation = nil )
    self << JParameter.new( name, type, documentation )
    return self
  end
  
  def << ( e )
    # Can't add anything to an attribute apart from documentation
    return e
  end
    
  def get_element()
    element = new_element "ownedOperation", { "xmi:type" => "uml:Operation",  "xmi:id" => @id, "name" => @name,  "visibility" => @visibility } 
    add_model_elements_to! element
    return element
  end
end

class JParameter < JModelElement
  attr_accessor :type
  def initialize( name, type = nil , documentation = nil )
    super name, documentation
    @type = type
  end
  
  def get_element()
    element = new_element "ownedParameter", { "xmi:type" => "uml:Parameter",  "xmi:id" => @id, "name" => @name, "visibility" => @visibility } 
    element.add_element "type", { "xmi:type" => @type.id } if type # href="http://www.omg.org/spec/UML/20090901/uml.xml#String"/> } 
    return element
  end
end

class JLiteral < JModelElement
  def initialize( name, documentation = nil )
    super name, documentation
  end

  def get_element()
    element = new_element "ownedLiteral", {"name" => @name,  "visibility" => "public", "xmi:id" => @id, "xmi:type" => "uml:EnumerationLiteral"}
    add_model_elements_to! element
    return element
  end

end

class JEnumeration < JModelElement
  attr_accessor :literals, :parents
  def initialize( name, documentation = nil )
    super name, documentation
    @literals = []
    @parents = {}
  end

  def add_parent( e )
    @parents[ e ] = nil if e.class == String              # It is a class name
    @parents[ e.name ] = e if e.class == JEnumeration     # It is a class
    return self
  end

  def << ( e )
    @literals << e if ( e.class == String ) || ( e.class == Array )
    @literals = @literals.flatten
    return e
  end
  
  def add_enumeration_literal( e )
    self << e
    return self
  end

  def get_element()
    element = new_element "ownedMember", { "isAbstract" => "false", "isLeaf" => "false", "name" => @name, "visibility" => "public", "xmi:id" => @id, "xmi:type" => "uml:Enumeration" }
    @literals.each {|l| element.add_element JLiteral.new( l ).get_element }
    @parents.values.each { | p | element.add_element( JGeneralization.new( p ).get_element )}
    add_model_elements_to! element
    return element
  end

end

class JMagicAssociation < JModelElement
  def initialize( c_1, r_1, m_1, m_2, r_2, c_2 )
    super()
    @class_1 = c_1
    @role_1 = r_1
    @multiplicity_1 = m_1
    @multiplicity_2 = m_2
    @role_2 = r_2
    @class_2 = c_2

    # Add private attributes to the classes
    @a1 = @class_1 << JAttribute.new( @role_2, @class_2, @multiplicity_2 )
    @a2 = @class_2 << JAttribute.new( @role_1, @class_1, @multiplicity_1 )
  end

  def get_element()
    element = new_element "packagedElement", { "xmi:type" => "uml:Association", "xmi:id" => @id, "name" => @name, "visibility" => "public" }
    element.add_element "memberEnd", { "xmi:idref" => @a1.id }
    element.add_element "memberEnd", { "xmi:idref" => @a2.id } 
    add_model_elements_to! element
    return element
  end
end

class JVPUMLAssociation < JModelElement
  def initialize( c_1, r_1, m_1, m_2, r_2, c_2 )
    super()
    @class_1 = c_1
    @role_1 = r_1
    @multiplicity_1 = m_1
    @multiplicity_2 = m_2
    @role_2 = r_2
    @class_2 = c_2
  end

  def get_element()
    element = new_element "packagedElement", { "xmi:type" => "uml:Association", "xmi:id" => @id, "name" => @name, "visibility" => "public" }

    # Member end 1
    e1 = element.add_element "memberEnd", { "xmi:idref" => @class_1.id }
    # Owned end 1
    element.add_element JOwnedEnd.new( @class_1, @role_1, @multiplicity_1, self ).get_element

    # Member end 2
    e2 = element.add_element "memberEnd", { "xmi:idref" => @class_2.id }
    # Owned end 2
    element.add_element JOwnedEnd.new( @class_2, @role_2, @multiplicity_2, self ).get_element

    add_model_elements_to! element
    return element
  end
end

class JAssociation < JModelElement
  def initialize( class_1, role_1, multiplicity_1, multiplicity_2, role_2, class_2 )
    super()
    @class_1 = class_1
    @role_1 = role_1
    @multiplicity_1 = multiplicity_1
    @multiplicity_2 = multiplicity_2
    @role_2 = role_2
    @class_2 = class_2
    
    # Add private attributes to the classes
    @a1 = @class_1 << JAttribute.new( @role_2, @class_2, @multiplicity_2 )
    @a2 = @class_2 << JAttribute.new( @role_1, @class_1, @multiplicity_1 )
  end

  def get_element()
    element = new_element "packagedElement", { "xmi:type" => "uml:Association", "xmi:id" => @id, "name" => @name, "visibility" => "public" }

    # Member end 1
    element.add_element "memberEnd", { "xmi:idref" => @a1.id }
    # Owned end 1
    element.add_element JOwnedEnd.new( @class_1, @role_1, @multiplicity_1, self ).get_element if $vp_uml

    # Member end 2
    element.add_element "memberEnd", { "xmi:idref" => @a2.id }
    # Owned end 2
    element.add_element JOwnedEnd.new( @class_2, @role_2, @multiplicity_2, self ).get_element if $vp_uml

    add_model_elements_to! element
    return element
  end
end

class JOwnedEnd < JModelElement
  def initialize( j_class, name, multiplicity, association )
    super name 
    @class = j_class
    @multiplicity = multiplicity
    @association = association
  end

  def get_element()
    element = new_element "ownedEnd", { "aggregation" => "none", "association" => @association.id, "isDerived" => "false", "isNavigable" => "true", "name" => @name, "type" => @class.id, "xmi:id" => @id, "xmi:type" => "uml:Property" }
    lv = element.add_element "lowerValue", { "value" => @multiplicity, "xmi:id" => lv.object_id.to_s(), "xmi:type" => "uml:LiteralString" } 
    return element
  end
end

if __FILE__ == $0
  # VP UML handles assocaitions differently than MagicDraw
  $vp_uml = false
  
  m = JModel.new( "MyModel" ) 
  
  # Classes and attributes 
  m.add_package( "MyPackage" ) 
  m.MyPackage
            .add_package( "MyNestedpackage" ) 
            .add_class( "C1", "Documentation for c1" )
            .C1
                .add_attribute( "c1a1", "Test", "Some documentation for c1a1" ) 
  
  # More packages
  m.add_package "NewAPIPackage" 
  m.NewAPIPackage.add_class( "C3" ) 
                 .C3.add_attribute( "c3a1", m.MyPackage.C1 ) 

  m.add_class( "C2", "Documentation for c2" ) 
   .C2.add_operation( "testOperation" ) 
      .testOperation.add_parameter( "p1" ) 
    
  # Add a generalization relationship between C1 (specific) and C2 (general)  
  m.MyPackage.C1.add_parent( m.C2 ) 

  # Enumerations
  m
    .add_enumeration( "E1" ) 
    .add_enumeration( "E2" ) 
    .E1.add_enumeration_literal( [ "Literal1", "Literal2", "Literal3" ] ) 
       .add_parent( m.E2 )  # Add a generalization relationship between E1 (specific) and E2 (general)
    # m.E1.junk # Test error handling

  # Associations
  m.add_association( m.MyPackage.C1, "role1", "*", "1", "role2", m.C2 ) 

  puts m.get_element
  File.open( "D:/test.xmi", "w+" ) {|f| f.write( m.get_element.to_s ) }

  #puts m.get_all_model_elements.select{|k,v| (v.class == JAttribute) && (v.type.class == String)}.keys
  #puts m.resolve_attributes
end