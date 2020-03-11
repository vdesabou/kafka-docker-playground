package io.confluent.developer;

import io.confluent.developer.avro.MusicInterest;
import io.confluent.developer.avro.TrackPurchase;
import io.confluent.developer.avro.Album;
import org.apache.kafka.streams.kstream.ValueJoiner;

public class MusicInterestJoiner implements ValueJoiner<TrackPurchase, Album, MusicInterest> {
    public MusicInterest apply(TrackPurchase trackPurchase, Album album) {
        return MusicInterest.newBuilder()
                .setId(album.getId() + "-" + trackPurchase.getId())
                .setGenre(album.getGenre())
                .setArtist(album.getArtist())
                .build();
    }
}