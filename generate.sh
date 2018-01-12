#!/bin/bash
#
# Generate a file containing all geographical Wikidata items that do not have an image (P18 property).
# Useful for photographers traveling to places with no network.

#FILENAME=java-bali
#MIN_LONGITUDE=105.1
#MAX_LONGITUDE=115.7
#MIN_LATITUDE=-8.9
#MAX_LATITUDE=-5.8

#FILENAME=shanghai
#MIN_LONGITUDE=121.202107
#MAX_LONGITUDE=121.978326
#MIN_LATITUDE=30.760658
#MAX_LATITUDE=31.525632

# Read and validate command-line arguments
if [ "$#" ne 5 ] ; then
  echo "Please enter miniumum longitude, maximum longitude, minimum latitude, maximum latitude, language code."
  exit 1
fi

regNum='^-?[0-9]+([.][0-9]+)?$'
regLan='^[a-zA-Z-]+$'
if ! [[ $1 =~ $regNum ]] ; then echo "Error: $0 is not a valid number"; exit 1
   elif ! [[ $2 =~ $regNum ]] ; then echo "Error: $1 is not a valid number"; exit 1
   elif ! [[ $3 =~ $regNum ]] ; then echo "Error: $2 is not a valid number"; exit 1
   elif ! [[ $4 =~ $regNum ]] ; then echo "Error: $3 is not a valid number"; exit 1
   elif ! [[ $5 =~ $regLan ]] ; then echo "Error: $4 is not a valid language code"; exit 1
fi

# Read and validate Longitude & Latitude values
if ![ ! -z $1 -a $1 -ge -180 -a $1 -le 178.9 ] ; then MIN_LONGITUDE = $1
else
  echo "The value $1 is invalid longitude value. Please reenter."; exit 1
fi

if ![ ! -z $2 -a $2 -ge -179 -a $2 -le 179.9 ] ; then MAX_LONGITUDE = $2
else
  echo "The value $2 is invalid longitude value. Please reenter."; exit 1
fi

if ![ ! -z $3 -a $3 -ge -180 -a $3 -le 178.9 ] ; then MIN_LATITUDE = $3
else
  echo "The value $3 is invalid latitude value. Please reenter."; exit 1
fi

if ![ ! -z $4 -a $4 -ge -179 -a $4 -le 179.9 ] ; then MAX_LATITUDE = $4
else
  echo "The value $4 is invalid latitude value. Please reenter."; exit 1
fi

###########################################################
GPX="$FILENAME.gpx"
KML="$FILENAME.kml"
cat gpx-header.txt > $GPX
cat kml-header.txt > $KML

INCREMENT=1
for LONGITUDE in `seq $MIN_LONGITUDE $INCREMENT $MAX_LONGITUDE`;
do
  echo "long loop $LONGITUDE"
  # Add missing zero to numbers like .7
  NEXT_LONGITUDE=`echo "x=$INCREMENT + $LONGITUDE; if(x>0 && x<1) print 0; x" | bc`

  for LATITUDE in `seq $MIN_LATITUDE $INCREMENT $MAX_LATITUDE`;
  do
    echo "lat loop $LATITUDE"
    # Add missing zero to numbers like .7
    NEXT_LATITUDE=`echo "x=$INCREMENT + $LATITUDE; if(x>0 && x<1) print 0; x" | bc`

    echo "Longitudes: $LONGITUDE -> $NEXT_LONGITUDE Latitudes: $LATITUDE -> $NEXT_LATITUDE"

    echo "SELECT
      ?item
      (SAMPLE(COALESCE(?en_label, ?fr_label, ?id_label, ?item_label)) as ?label)
      (SAMPLE(?location) as ?location)
      (GROUP_CONCAT(DISTINCT ?class_label ; separator=\",\") as ?class)
    WHERE {
      SERVICE wikibase:box {
        ?item wdt:P625 ?location .
        bd:serviceParam wikibase:cornerSouthWest \"Point($LONGITUDE $LATITUDE)\"^^geo:wktLiteral .
        bd:serviceParam wikibase:cornerNorthEast \"Point($NEXT_LONGITUDE $NEXT_LATITUDE)\"^^geo:wktLiteral .
      }
      MINUS {?item wdt:P18 ?image}
    
      MINUS {?item wdt:P582 ?endtime.}
      MINUS {?item wdt:P582 ?dissolvedOrAbolished.}
      MINUS {?item p:P31 ?instanceStatement. ?instanceStatement pq:P582 ?endtimeQualifier.}
    
      OPTIONAL {?item rdfs:label ?en_label . FILTER(LANG(?en_label) = \"en\")}
      OPTIONAL {?item rdfs:label ?fr_label . FILTER(LANG(?fr_label) = \"fr\")}
      OPTIONAL {?item rdfs:label ?vn_label . FILTER(LANG(?id_label) = \"id\")}
      OPTIONAL {?item rdfs:label ?item_label}

      OPTIONAL {?item wdt:P31 ?class. ?class rdfs:label ?class_label. FILTER(LANG(?class_label) = \"en\")}
    }
    GROUP BY ?item" | ../database-of-embassies/tools/query-wikidata.sh \
      | grep -i "<literal\|<uri>" | tr "\n" " " | sed -e "s/<uri>/\n<uri>/g" | grep wikidata > /tmp/items.txt

    while read ITEM; do
      ITEM_URL=`echo $ITEM | sed -e "s/^<uri>//" | sed -e "s/<.*//"`
      ITEM_NAME=`echo $ITEM | sed -e "s/.*<\/uri>\s*<literal[^>]*>\([^<]*\).*/\\1/"`
      ITEM_LONGITUDE=`echo $ITEM | sed -e "s/.*Point(\([-0-9E.]*\) [-0-9E.]*).*/\\1/"` # E: exponent is sometimes present
      ITEM_LATITUDE=`echo $ITEM | sed -e "s/.*Point([-0-9E.]* \([-0-9E.]*\)).*/\\1/"`
      ITEM_TYPE=`echo $ITEM | sed -e "s/.*<literal>\([^<]*\)<\/literal>$/\\1/"`

      #echo $ITEM
      #echo $ITEM_URL
      #echo $ITEM_NAME
      #echo $ITEM_LATITUDE
      #echo $ITEM_LONGITUDE
      #echo $ITEM_TYPE
      #echo ""

      if [ ! -z "$ITEM_TYPE" ]
      then
        ITEM_NAME="$ITEM_NAME ($ITEM_TYPE)"
      fi
      
      echo "<wpt lat='$ITEM_LATITUDE' lon='$ITEM_LONGITUDE'><name>$ITEM_NAME</name><url>$ITEM_URL</url></wpt>" >> $GPX
      echo "        <Placemark>
              <name>$ITEM_NAME</name>
              <description>$ITEM_URL</description>
              <Point>
                  <coordinates>$ITEM_LONGITUDE,$ITEM_LATITUDE</coordinates>
              </Point>
          </Placemark>" >> $KML
    done < /tmp/items.txt
  done
done

cat gpx-footer.txt >> $GPX
cat kml-footer.txt >> $KML

# Transform KML to KMZ per https://developers.google.com/kml/documentation/kmzarchives
DIRECTORY=wmpo # Any name is OK
rm -rf $DIRECTORY
mkdir $DIRECTORY
cp $FILENAME.kml $DIRECTORY/doc.kml
zip -r $DIRECTORY $DIRECTORY
mv $DIRECTORY.zip $FILENAME.kmz
rm -rf $DIRECTORY
