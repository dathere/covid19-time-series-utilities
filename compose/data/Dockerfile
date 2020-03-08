FROM debian:bullseye

ENV ROOTDIR /usr/local/
WORKDIR $ROOTDIR/

ADD ./compose/data/install_extras.sh $ROOTDIR/src/
RUN chmod 777 src/install_extras.sh
RUN src/install_extras.sh

#COPY ./covid19-ingest.sh /entrypoint.sh
#RUN sed -i 's/\r//' /entrypoint.sh
#RUN chmod +x /entrypoint.sh
#
#ENTRYPOINT ["/entrypoint.sh"]
