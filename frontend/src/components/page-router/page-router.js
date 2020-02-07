import React from 'react';
import {BrowserRouter, Route, Switch} from 'react-router-dom'
import {SongLinkPlayer} from "../song-link-player/song-link-player";
import SiteLayout from "../site-layout/site-layout";
import LoginPageWrapper from "../login-page/login-page-wrapper";
import AccountCreation from "../account-creation/account-creation";

export function PageRouter() {
	return (
		<BrowserRouter>
			<Switch>
				<Route path="/login" component={LoginPageWrapper}/>
				<Route path="/track-link/:trackId" component={SongLinkPlayer}/>
				<Route path="/create-account/:key" component={AccountCreation}/>
				<Route path="/" component={SiteLayout}/>
				<Route render={() => <h1>Yo dawg where the page at</h1>}/>
			</Switch>
		</BrowserRouter>
	)
}
