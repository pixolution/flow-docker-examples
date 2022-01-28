ARG image

FROM ${image}

USER root

# move pixolution flow plugin jar from /var/solr to WEB-INF/lib/
RUN find /var/solr -name "pixolution-flow*.jar" -exec mv "{}" /opt/solr/server/solr-webapp/webapp/WEB-INF/lib/ \;

# copy the module-jars
RUN find flow-jars/ -name "*.jar" -exec cp "{}" /opt/solr/server/solr-webapp/webapp/WEB-INF/lib/ \;

USER solr