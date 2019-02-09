import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hear2learn/app.dart';
import 'package:hear2learn/models/episode.dart';
import 'package:hear2learn/models/episode_action.dart';
import 'package:hear2learn/models/user_episode.dart';
import 'package:path/path.dart';

final Dio dio = Dio();

Future<List<Episode>> getDownloads() async {
  final App app = App();
  final UserEpisodeBean userEpisodeModel = app.models['user_episode'];

  final List<UserEpisode> episodes = await userEpisodeModel.getAll();
  return Future.wait(episodes.map((UserEpisode episode) => getEpisodeWithActions(episode)));
}

Future<Episode> getEpisodeWithActions(UserEpisode userEpisode) async {
  final App app = App();
  final EpisodeActionBean episodeActionModel = app.models['episode_action'];

  final Episode episode = userEpisode.getEpisodeFromDetails();
  final List<EpisodeAction> episodeActions = await episodeActionModel.findWhere(
    episodeActionModel.url.eq(episode.url)
  );
  episodeActions.forEach((EpisodeAction action) {
    if(action.type == EpisodeActionType.DOWNLOAD.toString()) {
      episode.downloadPath = action.details;
    }
    else if(action.type == EpisodeActionType.PLAY.toString()) {
      episode.setPlayerDetails(action.details);
    }
  });
  return episode;
}

Future<Episode> getUserEpisodeFromUrl(String url) async {
  final App app = App();
  final UserEpisodeBean userEpisodeModel = app.models['user_episode'];
  final UserEpisode userEpisode = await userEpisodeModel.findOneWhere(
    userEpisodeModel.url.eq(url)
  );
  return userEpisode?.getEpisodeFromDetails();
}

Future<void> downloadEpisode(Episode episode, {OnDownloadProgress onProgress}) async {
  final App app = App();
  final EpisodeActionBean episodeActionModel = app.models['episode_action'];
  final UserEpisodeBean userEpisodeModel = app.models['user_episode'];

  final String downloadId = EpisodeAction.createNewId();
  final String downloadPath = join(await app.getApplicationDownloadsPath(), '$downloadId.mp3');
  final EpisodeAction download = EpisodeAction(
    actionType: EpisodeActionType.DOWNLOAD,
    details: downloadPath,
    id: downloadId,
    url: episode.url,
  );

  await dio.download(episode.url, downloadPath, onProgress: onProgress);

  await episodeActionModel.insert(download);
  await userEpisodeModel.insert(
    UserEpisode(
      details: episode.toJson(),
      url: episode.url,
    )
  );

  episode.downloadPath = downloadPath;
  episode.progress = null;
}

Future<void> updateEpisodePosition(Episode episode, Duration position) async {
  final App app = App();
  final EpisodeActionBean episodeActionModel = app.models['episode_action'];
  EpisodeAction episodeAction = await episodeActionModel.findOneWhere(
    episodeActionModel.url.eq(episode.url)
      .and(episodeActionModel.type.eq(EpisodeActionType.PLAY.toString()))
  );
  episodeAction ??= EpisodeAction(
    actionType: EpisodeActionType.PLAY,
    url: episode.url,
  );

  await episodeActionModel.upsert(episodeAction.copyWith(
    details: episode.copyWith(position: position).getPlayerDetails(),
  ));
}

Future<void> deleteEpisode(Episode episode) async {
  final App app = App();
  final EpisodeActionBean episodeActionModel = app.models['episode_action'];
  final EpisodeAction download = await episodeActionModel.findOneWhere(episodeActionModel.url.eq(episode.url));
  await File(download.details).delete();
  await episodeActionModel.removeWhere(
    episodeActionModel.url.eq(episode.url)
      .and(episodeActionModel.type.eq(EpisodeActionType.DOWNLOAD.toString()))
  );
  episode.downloadPath = null;
}
